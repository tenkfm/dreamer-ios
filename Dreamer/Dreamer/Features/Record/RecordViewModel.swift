import CoreGraphics
import Foundation
import Observation

/// 08 Record: live transcript, timer and every way a recording can pause. No interruption loses
/// text: a call, the app going to the background, the lock screen or the time limit pause the
/// recording with the text so far, and "Continue" adds to it.
@MainActor
@Observable
final class RecordViewModel {
    /// What stands between the user and the microphone.
    enum Access: Equatable {
        case unknown
        /// Our own explanation, shown before the system alerts.
        case prePrompt
        case listening
        /// Refused or restricted: Settings or typing.
        case blocked(SpeechPermission)
    }

    /// Why the recording is paused (nil while recording or before the first start).
    enum PauseReason: Equatable {
        case user
        /// A call, Siri or an alarm took the microphone.
        case interruption
        /// The app went to the background or the phone was locked.
        case background
        case timeLimit
    }

    /// Why the server could not write the recording down, and what the user can do.
    enum TranscriptionFailure: Equatable {
        /// The upload did not go through; the audio is still here, trying again resends it.
        case offline
        case uploadFailed
        /// 20 server transcriptions a day.
        case limitReached
        /// The server heard the audio but has no text (the audio is gone there): type it.
        case unavailable
        case noWords

        init(uploadError error: APIError) {
            switch error {
            case .offline, .timeout: self = .offline
            case .server(let server) where server.code == .limitReached || server.code == .rateLimited:
                self = .limitReached
            default: self = .uploadFailed
            }
        }

        init(transcribeError error: APIError) {
            switch error.code {
            case .limitReached, .rateLimited: self = .limitReached
            default: self = .unavailable
            }
        }

        var message: String {
            switch self {
            case .offline: String(localized: "You’re offline. Try again when you’re connected, or type your dream.")
            case .uploadFailed: String(localized: "We couldn’t send your recording. Try again, or type your dream.")
            case .limitReached: String(localized: "That’s all the voice we can write down today. Please type your dream.")
            case .unavailable: String(localized: "We couldn’t write down your recording. Please type your dream.")
            case .noWords: String(localized: "We couldn’t hear any words. Continue recording or type your dream.")
            }
        }

        /// The recording is still on the phone, so sending it again makes sense.
        var canRetry: Bool { self == .offline || self == .uploadFailed }
    }

    enum ServerTranscription: Equatable {
        case working
        case failed(TranscriptionFailure)
    }

    /// What "I’m done" produced.
    struct RecordedDream: Equatable {
        var transcript: String
        /// Set when the text came from the server fallback; the dream links to it.
        var recordingID: String?
    }

    /// Editable so the keyboard fallback can correct it.
    var transcript = ""
    private(set) var elapsedSeconds = 0
    private(set) var isRecording = false
    var isTyping = false
    /// The last 24 microphone levels (0...1), newest last, for the waveform.
    private(set) var levels: [CGFloat] = Array(repeating: 0, count: RecordViewModel.barCount)
    /// Recognition stopped by itself (unavailable, failed).
    private(set) var speechError: SpeechError?
    private(set) var access: Access = .unknown
    private(set) var pauseReason: PauseReason?
    /// This recording has no live text; it is written down on the server at "I’m done".
    private(set) var isLiveTextUnavailable = false
    private(set) var serverTranscription: ServerTranscription?

    static let barCount = 24
    /// A dream told longer than this is cut; a warning comes before.
    static let timeLimit = 5 * 60
    static let warningBeforeLimit = 30

    private let speech: any SpeechService
    private let permissions: any SpeechPermissions
    private let tick: Duration
    private let analytics: any Analytics
    @ObservationIgnored private var hasReportedStart = false
    /// The keyboard was used: the dream counts as typed.
    @ObservationIgnored private var usedKeyboard = false
    /// Nil when the serverSttFallback flag is off (or in mock mode).
    private let transcriber: (any RecordingTranscriber)?
    /// Taken from the speech service, kept until it is uploaded (or the flow is abandoned).
    @ObservationIgnored private var pendingAudio: RecordedAudio?
    /// Text from before the current listening run; a resumed run continues after it.
    @ObservationIgnored private var textBeforeRun = ""
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(speech: any SpeechService, permissions: any SpeechPermissions = MockSpeechPermissions(),
         transcriber: (any RecordingTranscriber)? = nil, analytics: any Analytics = NoopAnalytics(),
         tick: Duration = .seconds(1)) {
        self.speech = speech
        self.analytics = analytics
        self.permissions = permissions
        self.transcriber = transcriber
        self.tick = tick
    }

    // MARK: Access

    /// The Record screen appeared: listen at once when allowed, otherwise explain first.
    func appeared() {
        switch permissions.current {
        case .granted:
            access = .listening
            start()
        case .notDetermined:
            access = .prePrompt
        case .denied, .restricted:
            access = .blocked(permissions.current)
        }
    }

    /// "Allow microphone" on the pre-prompt: the system alerts, then listen or explain the refusal.
    func requestAccess() async {
        let answer = await permissions.request()
        if answer == .granted {
            access = .listening
            start()
        } else {
            access = .blocked(answer)
        }
    }

    /// No microphone: write the dream down instead (the main flow never depends on permissions).
    func typeInstead() {
        usedKeyboard = true
        pause(.user)
        serverTranscription = nil
        isTyping = true
    }

    // MARK: Status

    var timerText: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    var trimmedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var secondsLeft: Int { max(0, Self.timeLimit - elapsedSeconds) }

    /// "30 seconds left" in the last half minute.
    var isNearTimeLimit: Bool { isRecording && secondsLeft <= Self.warningBeforeLimit }

    var canContinue: Bool {
        !isRecording && pauseReason != nil && pauseReason != .timeLimit && access == .listening && !isTranscribing
    }

    var isTranscribing: Bool { serverTranscription == .working }

    /// Audio the server can write down (no live text needed).
    private var hasServerAudio: Bool {
        transcriber != nil && speech.keepsAudio && (pendingAudio != nil || Double(elapsedSeconds) >= RecordedAudio.minimumDuration)
    }

    /// "I’m done" is possible with words, or with audio the server can write down.
    var canFinish: Bool {
        !isTranscribing && (!trimmedTranscript.isEmpty || hasServerAudio)
    }

    var pauseMessage: String? {
        switch pauseReason {
        case .interruption: String(localized: "Paused for a call. Your words are saved.")
        case .background: String(localized: "Paused while Mooncatch was away. Your words are saved.")
        case .timeLimit: String(localized: "That’s five minutes - your dream is saved. Tap “I’m done”.")
        case .user, nil:
            if case .failed(let failure) = serverTranscription { failure.message } else { nil }
        }
    }

    // MARK: Recording

    func start() {
        guard !isRecording, elapsedSeconds < Self.timeLimit else { return }
        isRecording = true
        if !hasReportedStart {
            hasReportedStart = true
            analytics.track(.recordStarted)
        }
        pauseReason = nil
        speechError = nil
        serverTranscription = nil
        textBeforeRun = trimmedTranscript
        let stream = speech.start()
        listenTask = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.handle(event)
                }
            } catch {
                self?.speechError = (error as? SpeechError) ?? .audio(String(describing: type(of: error)))
                self?.pause(.interruption)
            }
        }
        timerTask = Task { [weak self, tick] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard !Task.isCancelled else { return }
                self?.secondPassed()
            }
        }
    }

    /// "Continue" after a pause: the new words follow the saved ones.
    func resume() {
        guard canContinue else { return }
        start()
    }

    private func secondPassed() {
        elapsedSeconds += 1
        if elapsedSeconds >= Self.timeLimit { pause(.timeLimit) }
    }

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .transcript(let text):
            transcript = Self.join(textBeforeRun, text)
        case .level(let level):
            levels.removeFirst()
            levels.append(CGFloat(level))
        case .interrupted:
            pause(.interruption)
        case .liveTextUnavailable:
            isLiveTextUnavailable = true
        }
    }

    /// Stops listening and keeps everything said so far.
    func pause(_ reason: PauseReason) {
        guard isRecording else { return }
        speech.stop()
        listenTask?.cancel()
        timerTask?.cancel()
        listenTask = nil
        timerTask = nil
        levels = Array(repeating: 0, count: Self.barCount)
        isRecording = false
        pauseReason = reason
    }

    /// Leaving the screen for good ("I’m done", close).
    func stop() {
        pause(.user)
    }

    /// The app is leaving the foreground (home, lock screen, app switcher).
    func enteredBackground() {
        pause(.background)
    }

    /// Keyboard button: stop listening and let the user type or correct the text.
    func switchToTyping() {
        usedKeyboard = true
        pause(.user)
        serverTranscription = nil
        isTyping = true
    }

    // MARK: Finishing

    /// "I’m done": the transcript from the device or, when it gave no text, from the server
    /// (upload, then transcribe). Nil when there is nothing yet; `serverTranscription` says why.
    func finish() async -> RecordedDream? {
        guard !isTranscribing else { return nil }
        stop()
        if !trimmedTranscript.isEmpty {
            // The device heard the words: the audio is not needed and does not stay.
            discardAudio()
            analytics.track(.recordFinished(seconds: elapsedSeconds, input: usedKeyboard ? .text : .voice))
            return RecordedDream(transcript: trimmedTranscript)
        }
        guard let transcriber else { return nil }
        guard let audio = pendingAudio ?? speech.takeRecording() else {
            serverTranscription = .failed(.noWords)
            return nil
        }
        pendingAudio = audio
        serverTranscription = .working

        let recordingID: String
        do {
            recordingID = try await transcriber.upload(audio)
        } catch {
            // Still on the phone: "Try again" resends it.
            serverTranscription = .failed(TranscriptionFailure(uploadError: error))
            return nil
        }
        audio.delete()
        pendingAudio = nil

        do {
            let text = try await transcriber.transcribe(recordingID: recordingID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                serverTranscription = .failed(.noWords)
                return nil
            }
            transcript = text
            serverTranscription = nil
            analytics.track(.recordFinished(seconds: elapsedSeconds, input: .voice))
            return RecordedDream(transcript: text, recordingID: recordingID)
        } catch {
            serverTranscription = .failed(TranscriptionFailure(transcribeError: error))
            return nil
        }
    }

    /// The flow is closed: no recording stays on the phone.
    func discardAudio() {
        speech.discardRecording()
        pendingAudio?.delete()
        pendingAudio = nil
    }

    private static func join(_ head: String, _ tail: String) -> String {
        let tail = tail.trimmingCharacters(in: .whitespaces)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}
