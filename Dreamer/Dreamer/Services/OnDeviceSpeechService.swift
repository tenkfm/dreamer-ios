@preconcurrency import AVFoundation
import Foundation
import os
@preconcurrency import Speech

/// Live transcription on the device: the microphone through AVAudioEngine into SFSpeechRecognizer.
/// Recognition stays on the device where the model is available (works in airplane mode). One
/// recognition request is limited to about a minute, so a long dream is told across several
/// requests: each finished segment is kept and the next one continues after it.
///
/// With `keepsAudio` (the serverSttFallback flag) the audio is also written to a temporary m4a, so
/// a dream that got no text on the device (a language the iPhone cannot recognize, a failed
/// recognizer) can still be transcribed on the server when the user is done.
@MainActor
final class OnDeviceSpeechService: SpeechService {
    private let locale: Locale
    let keepsAudio: Bool
    private var session: SpeechSession?
    /// Spans every listening run of one recording (pauses included) until taken or discarded.
    private var audioFile: AudioRecordingFile?

    init(locale: Locale = .current, keepsAudio: Bool = false) {
        self.locale = locale
        self.keepsAudio = keepsAudio
    }

    /// The recognizer for the user's language. When the device cannot recognize it: none if the
    /// server will transcribe the audio, US English otherwise (better than no text at all).
    nonisolated static func recognizer(for locale: Locale, serverFallback: Bool = false) -> SFSpeechRecognizer? {
        if let native = SFSpeechRecognizer(locale: locale), native.isAvailable { return native }
        if serverFallback { return nil }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() -> AsyncThrowingStream<SpeechEvent, any Error> {
        stop()
        let (stream, continuation) = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        let recognizer = Self.recognizer(for: locale, serverFallback: keepsAudio).flatMap { $0.isAvailable ? $0 : nil }
        if keepsAudio && audioFile == nil {
            audioFile = try? AudioRecordingFile(url: RecordingFiles.newFileURL())
        }
        guard recognizer != nil || audioFile != nil else {
            continuation.finish(throwing: SpeechError.unavailable)
            return stream
        }
        if recognizer == nil { continuation.yield(.liveTextUnavailable) }
        let session = SpeechSession(recognizer: recognizer, audioFile: audioFile, continuation: continuation)
        self.session = session
        do {
            try session.begin()
        } catch {
            session.end()
            continuation.finish(throwing: error)
        }
        continuation.onTermination = { _ in Task { @MainActor in session.end() } }
        return stream
    }

    func stop() {
        session?.end()
        session = nil
    }

    func takeRecording() -> RecordedAudio? {
        stop()
        guard let file = audioFile else { return nil }
        audioFile = nil
        let audio = file.finish()
        guard audio.duration >= RecordedAudio.minimumDuration else {
            audio.delete()
            return nil
        }
        return audio
    }

    func discardRecording() {
        stop()
        audioFile?.finish().delete()
        audioFile = nil
    }
}

/// One recording: the audio engine, the rolling recognition requests and the stitched transcript.
/// Callbacks arrive on the audio and recognition threads, so the mutable state sits behind a lock.
private final class SpeechSession: @unchecked Sendable {
    /// Nil when there is no live text, only the audio for the server.
    private let recognizer: SFSpeechRecognizer?
    private let audioFile: AudioRecordingFile?
    private let continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation
    private let engine = AVAudioEngine()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var stitcher = TranscriptStitcher()
        var meter = AudioLevelMeter()
        var ended = false
    }

    private var observers: [NSObjectProtocol] = []

    init(recognizer: SFSpeechRecognizer?, audioFile: AudioRecordingFile?,
         continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation) {
        self.recognizer = recognizer
        self.audioFile = audioFile
        self.continuation = continuation
    }

    /// A call, Siri or an alarm takes the audio session: the text so far is kept (it was already
    /// sent), the recording ends and the screen offers to continue.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        let stopForInterruption: @Sendable (Notification) -> Void = { [weak self] notification in
            if notification.name == AVAudioSession.interruptionNotification {
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
            }
            self?.continuation.yield(.interrupted)
            self?.end()
        }
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil, using: stopForInterruption),
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil, using: stopForInterruption)
        ]
    }

    func begin() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
        // A recording session mutes haptics by default: the mic's knock on Home (still playing when
        // recording starts), the start and stop ticks and the time-limit warning were all silent.
        try? audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try audio.setActive(true, options: .notifyOthersOnDeactivation)

        startRequest()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechError.audio("No microphone input") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        observeInterruptions()
    }

    func end() {
        let (task, request) = state.withLock { state -> (SFSpeechRecognitionTask?, SFSpeechAudioBufferRecognitionRequest?) in
            guard !state.ended else { return (nil, nil) }
            state.ended = true
            defer { state.task = nil; state.request = nil }
            return (state.task, state.request)
        }
        guard task != nil || request != nil || engine.isRunning else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        continuation.finish()
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        let (request, level) = state.withLock { state in
            (state.request, state.meter.level(of: buffer))
        }
        request?.append(buffer)
        audioFile?.append(buffer)
        if let level { continuation.yield(.level(level)) }
    }

    /// A new recognition request; the previous one's text is already committed.
    private func startRequest() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        if #available(iOS 16, *) { request.addsPunctuation = true }

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error, request: request)
        }
        state.withLock {
            $0.request = request
            $0.task = task
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: (any Error)?, request: SFSpeechAudioBufferRecognitionRequest) {
        let (text, isCurrent, ended) = state.withLock { state -> (String?, Bool, Bool) in
            let isCurrent = state.request === request
            guard isCurrent, let result else { return (nil, isCurrent, state.ended) }
            let formatted = result.bestTranscription.formattedString
            var text = result.isFinal ? state.stitcher.commit(formatted) : state.stitcher.update(partial: formatted)
            // iOS 17+ closes an utterance at a pause without ending the request, and the next
            // partials hold only the new one; the metadata marks that close. Without keeping the
            // closed utterance, the next phrase replaced the previous one on screen.
            if !result.isFinal, result.speechRecognitionMetadata != nil {
                text = state.stitcher.endUtterance()
            }
            return (text, isCurrent, state.ended)
        }
        if let text { continuation.yield(.transcript(text)) }
        guard isCurrent, !ended else { return }

        // The request finished on its own (the ~1 minute limit, or a pause the recognizer took as
        // the end): keep listening with a new one. The text so far is committed already.
        if result?.isFinal == true || error != nil {
            if let error, !Self.isRecoverable(error) {
                if audioFile != nil {
                    // The audio goes on; the server writes it down at the end.
                    state.withLock { $0.request = nil; $0.task = nil }
                    continuation.yield(.liveTextUnavailable)
                    return
                }
                continuation.finish(throwing: error)
                end()
                return
            }
            request.endAudio()
            startRequest()
        }
    }

    /// "No speech detected" and the request time limit end a request, not the recording.
    private static func isRecoverable(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "kAFAssistantErrorDomain" && [203, 216, 301, 1110].contains(nsError.code)
    }
}

/// Joins the finished recognition segments with the one being recognized. A segment ends with a
/// request (the ~1 minute limit) or with an utterance inside it (a pause, on iOS 17+).
struct TranscriptStitcher: Equatable, Sendable {
    private(set) var committed = ""
    private(set) var partial = ""
    /// What this request's closed utterances said: a recognizer that does not start over after a
    /// pause repeats it at the head of its next partials, and the repeat is dropped.
    private var heardInRequest = ""

    var text: String { Self.join(committed, partial) }

    /// The current segment changed; returns the whole transcript.
    mutating func update(partial new: String) -> String {
        let new = Self.dropping(heardInRequest, from: new)
        // A pause can start a new utterance with no signal at all: a partial far shorter than the
        // last one that no longer begins like it is new speech, and the old text is kept.
        if Self.startsOver(from: partial, to: new) { closeUtterance() }
        partial = new
        return text
    }

    /// The request is final; the next one starts empty.
    mutating func commit(_ final: String) -> String {
        partial = Self.dropping(heardInRequest, from: final)
        closeUtterance()
        heardInRequest = ""
        return committed
    }

    /// The recognizer closed an utterance (a pause) and goes on in the same request: what it heard
    /// is kept, and what follows is added after it instead of replacing it.
    mutating func endUtterance() -> String {
        closeUtterance()
        return committed
    }

    private mutating func closeUtterance() {
        let segment = partial.trimmingCharacters(in: .whitespaces)
        partial = ""
        guard !segment.isEmpty else { return }
        committed = Self.join(committed, segment)
        heardInRequest = Self.join(heardInRequest, segment)
    }

    private static func startsOver(from old: String, to new: String) -> Bool {
        guard let oldFirst = words(old).first, let newFirst = words(new).first else { return false }
        return new.count * 2 < old.count && oldFirst != newFirst
    }

    /// `text` without a leading repeat of `head` (compared by words, ignoring case and punctuation).
    private static func dropping(_ head: String, from text: String) -> String {
        let repeated = words(head)
        guard !repeated.isEmpty, words(text).starts(with: repeated) else { return text }
        var remaining = repeated.count
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let rest = tokens.drop { token in
            guard remaining > 0 else { return false }
            // Tokens of punctuation alone are no word: they go with the repeat.
            if !normalized(token).isEmpty { remaining -= 1 }
            return true
        }
        return rest.joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(normalized).filter { !$0.isEmpty }
    }

    private static func normalized(_ token: Substring) -> String {
        token.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func join(_ head: String, _ tail: String) -> String {
        let head = head.trimmingCharacters(in: .whitespaces)
        let tail = tail.trimmingCharacters(in: .whitespaces)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}

/// Turns audio buffers into a 0...1 level for the waveform, about 20 times a second.
struct AudioLevelMeter: Sendable {
    /// Quieter than this is silence (dBFS).
    var floorDecibels: Float = -50
    var interval: TimeInterval = 0.05
    private var lastEmit: TimeInterval = 0
    private var smoothed: Float = 0

    init(floorDecibels: Float = -50, interval: TimeInterval = 0.05) {
        self.floorDecibels = floorDecibels
        self.interval = interval
    }

    /// Nil between emissions.
    mutating func level(of buffer: AVAudioPCMBuffer, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Float? {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        return level(rms: (sum / Float(buffer.frameLength)).squareRoot(), now: now)
    }

    mutating func level(rms: Float, now: TimeInterval) -> Float? {
        let decibels = 20 * log10(max(rms, 1e-7))
        let normalized = min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
        // Fast attack, slow release: bars jump with a syllable and settle gently.
        smoothed = normalized > smoothed ? normalized : smoothed * 0.8 + normalized * 0.2
        guard now - lastEmit >= interval else { return nil }
        lastEmit = now
        return smoothed
    }
}
