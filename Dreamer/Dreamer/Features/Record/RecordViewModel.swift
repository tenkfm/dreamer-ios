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

    private let speech: any SpeechService
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(speech: any SpeechService) {
        self.speech = speech
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
        let stream = speech.start()
        listenTask = Task { [weak self] in
            for await text in stream {
                self?.transcript = text
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

    func stop() {
        speech.stop()
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
