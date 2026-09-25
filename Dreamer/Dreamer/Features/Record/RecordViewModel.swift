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
