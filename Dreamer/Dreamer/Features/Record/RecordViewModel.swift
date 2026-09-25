import CoreGraphics
import Foundation
import Observation

/// 08 Record: live transcript and timer.
@MainActor
@Observable
final class RecordViewModel {
    /// Editable so the keyboard fallback can correct it.
    var transcript = ""
    private(set) var elapsedSeconds = 0
    private(set) var isRecording = false
    var isTyping = false
    /// The last 24 microphone levels (0...1), newest last, for the waveform.
    private(set) var levels: [CGFloat] = Array(repeating: 0, count: RecordViewModel.barCount)
    /// Recognition stopped by itself (unavailable, failed).
    private(set) var speechError: SpeechError?

    static let barCount = 24

    /// What stands between the user and the microphone.
    enum Access: Equatable {
        case unknown
        /// Our own explanation, shown before the system alerts.
        case prePrompt
        case listening
        /// Refused or restricted: Settings or typing.
        case blocked(SpeechPermission)
    }

    private(set) var access: Access = .unknown

    private let speech: any SpeechService
    private let permissions: any SpeechPermissions
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(speech: any SpeechService, permissions: any SpeechPermissions = MockSpeechPermissions()) {
        self.speech = speech
        self.permissions = permissions
    }

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
        stop()
        isTyping = true
    }

    var timerText: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    var trimmedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        speechError = nil
        let stream = speech.start()
        listenTask = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.handle(event)
                }
            } catch {
                self?.speechError = (error as? SpeechError) ?? .audio(String(describing: type(of: error)))
                self?.stop()
            }
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.elapsedSeconds += 1
            }
        }
    }

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .transcript(let text):
            transcript = text
        case .level(let level):
            levels.removeFirst()
            levels.append(CGFloat(level))
        }
    }

    func stop() {
        speech.stop()
        levels = Array(repeating: 0, count: Self.barCount)
        listenTask?.cancel()
        timerTask?.cancel()
        listenTask = nil
        timerTask = nil
        isRecording = false
    }

    /// Keyboard button: stop listening and let the user type or correct the text.
    func switchToTyping() {
        stop()
        isTyping = true
    }
}
