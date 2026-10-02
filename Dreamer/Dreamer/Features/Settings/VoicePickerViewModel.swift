import AVFoundation
import Foundation
import Observation

/// Settings -> Voice: the voices with a preview each, filtered by gender on the device. A tap on a
/// row picks the voice at once and saves it in the background; a tap on play only listens.
@MainActor
@Observable
final class VoicePickerViewModel {
    enum Filter: CaseIterable, Hashable {
        case all, male, female

        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .male: String(localized: "Male")
            case .female: String(localized: "Female")
            }
        }
    }

    enum LoadState: Equatable { case loading, loaded, failed }

    var filter: Filter = .all
    private(set) var voices: [Voice] = []
    private(set) var loadState: LoadState = .loading
    /// The checkmark: moves on the tap, before the server confirms.
    private(set) var selectedID: String
    /// The voice whose preview is playing.
    private(set) var playingID: String?
    var toastMessage: String?
    private(set) var haptic: HapticEvent?

    private let appState: AppState
    private let service: any VoiceService
    private let player: any VoicePlayback
    /// The last voice the server confirmed: where the checkmark returns after a failed save.
    private var confirmedID: String
    /// Only the newest pick's answer counts when picks overlap.
    private var latestPick = 0

    init(appState: AppState, service: any VoiceService, player: any VoicePlayback) {
        self.appState = appState
        self.service = service
        self.player = player
        selectedID = appState.voiceID
        confirmedID = appState.voiceID
        player.onEnd = { [weak self] in self?.playingID = nil }
        player.onFailure = { [weak self] in self?.stopPreview() }
    }

    /// Neutral voices show only under All.
    var visibleVoices: [Voice] {
        switch filter {
        case .all: voices
        case .male: voices.filter { $0.gender == .male }
        case .female: voices.filter { $0.gender == .female }
        }
    }

    /// Asked every time the screen opens: a preview the server was still making may be ready now.
    func load() async {
        if voices.isEmpty { loadState = .loading }
        do {
            voices = try await service.voices().items
            loadState = .loaded
            // Names the current voice for the Settings row (it may have been picked elsewhere).
            if let current = voices.first(where: { $0.id == confirmedID }) {
                appState.setVoice(id: current.id, name: current.name)
            }
        } catch {
            if voices.isEmpty { loadState = .failed }
        }
    }

    // MARK: Preview

    /// Play, or stop the one playing. One preview at a time: another one stops it.
    func togglePreview(_ voice: Voice) {
        if playingID == voice.id {
            stopPreview()
            return
        }
        guard let url = voice.previewURL else { return }
        player.stop()
        // The session of Listen on the dream screen.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.load(url)
        player.play()
        playingID = voice.id
    }

    /// Leaving the screen or the app.
    func stopPreview() {
        guard playingID != nil else { return }
        player.stop()
        playingID = nil
    }

    // MARK: Pick

    func select(_ voice: Voice) async {
        guard voice.id != selectedID else { return }
        selectedID = voice.id
        latestPick += 1
        let pick = latestPick
        do {
            let profile = try await service.setVoice(voice.id)
            guard pick == latestPick else { return }
            confirmedID = profile.voice
            selectedID = profile.voice
            appState.setVoice(id: profile.voice, name: voices.first { $0.id == profile.voice }?.name)
        } catch {
            guard pick == latestPick else { return }
            selectedID = confirmedID
            haptic = HapticEvent(.error)
            toastMessage = String(localized: "Couldn’t save your voice. Try again.")
            // The voice left the catalog while the screen was open: show the list as it is now.
            if case .server(let server) = error, server.code == .validationFailed { await load() }
        }
    }
}
