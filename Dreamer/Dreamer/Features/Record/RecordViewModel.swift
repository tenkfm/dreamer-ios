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

    static let barCount = 24
    /// A dream told longer than this is cut; a warning comes before.
    static let timeLimit = 5 * 60
    static let warningBeforeLimit = 30

    private let speech: any SpeechService
    private let permissions: any SpeechPermissions
    private let tick: Duration
    /// Text from before the current listening run; a resumed run continues after it.
    @ObservationIgnored private var textBeforeRun = ""
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(speech: any SpeechService, permissions: any SpeechPermissions = MockSpeechPermissions(),
         tick: Duration = .seconds(1)) {
        self.speech = speech
        self.permissions = permissions
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
        pause(.user)
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

    var canContinue: Bool { !isRecording && pauseReason != nil && pauseReason != .timeLimit && access == .listening }

    var pauseMessage: String? {
        switch pauseReason {
        case .interruption: "Paused for a call. Your words are saved."
        case .background: "Paused while Dreamer was away. Your words are saved."
        case .timeLimit: "That’s five minutes - your dream is saved. Tap “I’m done”."
        case .user, nil: nil
        }
    }

    // MARK: Recording

    func start() {
        guard !isRecording, elapsedSeconds < Self.timeLimit else { return }
        isRecording = true
        pauseReason = nil
        speechError = nil
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
        pause(.user)
        isTyping = true
    }

    private static func join(_ head: String, _ tail: String) -> String {
        let tail = tail.trimmingCharacters(in: .whitespaces)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}
