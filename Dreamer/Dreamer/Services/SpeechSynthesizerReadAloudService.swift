import AVFoundation
import Observation

/// Reads text aloud with the on-device voice (phase 1). Progress follows the spoken range.
@MainActor
@Observable
final class SpeechSynthesizerReadAloudService: NSObject, ReadAloudService {
    private(set) var state: ReadAloudState = .idle
    private(set) var progress: Double = 0

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentText: String?
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ text: String) {
        if state == .paused, text == currentText {
            synthesizer.continueSpeaking()
            state = .playing
            return
        }
        stop()
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47
        currentText = text
        currentUtterance = ObjectIdentifier(utterance)
        progress = 0
        state = .playing
        synthesizer.speak(utterance)
    }

    func pause() {
        guard state == .playing else { return }
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
    }

    func stop() {
        currentUtterance = nil
        currentText = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .idle
        progress = 0
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    fileprivate func handleProgress(_ value: Double, utterance: ObjectIdentifier) {
        guard utterance == currentUtterance else { return }
        progress = value
    }

    fileprivate func handleFinish(utterance: ObjectIdentifier) {
        guard utterance == currentUtterance else { return }
        progress = 1
        state = .idle
        currentText = nil
        currentUtterance = nil
    }
}

extension SpeechSynthesizerReadAloudService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let total = max(utterance.speechString.utf16.count, 1)
        let value = Double(characterRange.location + characterRange.length) / Double(total)
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.handleProgress(value, utterance: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.handleFinish(utterance: id) }
    }
}
