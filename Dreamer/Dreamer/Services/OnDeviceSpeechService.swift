@preconcurrency import AVFoundation
import Foundation
import os
@preconcurrency import Speech

/// Live transcription on the device: the microphone through AVAudioEngine into SFSpeechRecognizer.
/// Recognition stays on the device where the model is available (works in airplane mode). One
/// recognition request is limited to about a minute, so a long dream is told across several
/// requests: each finished segment is kept and the next one continues after it.
@MainActor
final class OnDeviceSpeechService: SpeechService {
    private let locale: Locale
    private var session: SpeechSession?

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// The recognizer for the user's language, or US English when the device cannot recognize it.
    static func recognizer(for locale: Locale) -> SFSpeechRecognizer? {
        if let native = SFSpeechRecognizer(locale: locale), native.isAvailable { return native }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() -> AsyncThrowingStream<SpeechEvent, any Error> {
        stop()
        let (stream, continuation) = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        guard let recognizer = Self.recognizer(for: locale), recognizer.isAvailable else {
            continuation.finish(throwing: SpeechError.unavailable)
            return stream
        }
        let session = SpeechSession(recognizer: recognizer, continuation: continuation)
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
}

/// One recording: the audio engine, the rolling recognition requests and the stitched transcript.
/// Callbacks arrive on the audio and recognition threads, so the mutable state sits behind a lock.
private final class SpeechSession: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
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

    init(recognizer: SFSpeechRecognizer, continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation) {
        self.recognizer = recognizer
        self.continuation = continuation
    }

    func begin() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
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
    }

    func end() {
        let (task, request) = state.withLock { state -> (SFSpeechRecognitionTask?, SFSpeechAudioBufferRecognitionRequest?) in
            guard !state.ended else { return (nil, nil) }
            state.ended = true
            defer { state.task = nil; state.request = nil }
            return (state.task, state.request)
        }
        guard task != nil || request != nil || engine.isRunning else { return }
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
        if let level { continuation.yield(.level(level)) }
    }

    /// A new recognition request; the previous one's text is already committed.
    private func startRequest() {
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
            let text = result.isFinal
                ? state.stitcher.commit(result.bestTranscription.formattedString)
                : state.stitcher.update(partial: result.bestTranscription.formattedString)
            return (text, isCurrent, state.ended)
        }
        if let text { continuation.yield(.transcript(text)) }
        guard isCurrent, !ended else { return }

        // The request finished on its own (the ~1 minute limit, or a pause the recognizer took as
        // the end): keep listening with a new one. The text so far is committed already.
        if result?.isFinal == true || error != nil {
            if let error, !Self.isRecoverable(error) {
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

/// Joins the finished recognition segments with the one being recognized.
struct TranscriptStitcher: Equatable, Sendable {
    private(set) var committed = ""
    private(set) var partial = ""

    var text: String { Self.join(committed, partial) }

    /// The current segment changed; returns the whole transcript.
    mutating func update(partial: String) -> String {
        self.partial = partial
        return text
    }

    /// The current segment is final; the next one starts empty.
    mutating func commit(_ final: String) -> String {
        committed = Self.join(committed, final)
        partial = ""
        return committed
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
