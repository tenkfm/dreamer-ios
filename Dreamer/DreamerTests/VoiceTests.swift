import Foundation
import os
import Testing
@testable import Dreamer

struct VoiceContractTests {
    @Test func theVoiceListAndTheProfilesVoiceMap() async throws {
        let list = try await ContractExamples.client("listVoices", status: 200).voices()
        #expect(list.defaultVoiceID == "clint")
        #expect(list.items.map(\.id) == ["clint", "eve"])
        #expect(list.items[0].isDefault && list.items[0].gender == .male)
        #expect(list.items[1].previewURL?.pathExtension == "mp3")
        let profile = try await ContractExamples.client("getProfile", status: 200).profile()
        #expect(profile.voice == "clint")
    }
}

/// The voice list from a script; counts the calls and can refuse the pick.
final class ScriptedVoices: VoiceService, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(list: VoiceList, failure: APIError?, listCalls: Int, picks: [String])>

    init(_ list: VoiceList = VoiceFixtures.list, failure: APIError? = nil) {
        state = OSAllocatedUnfairLock(initialState: (list, failure, 0, []))
    }

    var listCalls: Int { state.withLock { $0.listCalls } }
    var picks: [String] { state.withLock { $0.picks } }

    func voices() async throws(APIError) -> VoiceList {
        state.withLock { $0.listCalls += 1; return $0.list }
    }

    func setVoice(_ id: String) async throws(APIError) -> UserProfile {
        try state.withLock { state -> Result<UserProfile, APIError> in
            state.picks.append(id)
            if let failure = state.failure { return .failure(failure) }
            return .success(UserProfile(id: "u", email: nil, name: nil, goal: nil, preferredLens: .psychology,
                                        reminder: .init(enabled: false, time: "07:00"), timezone: "UTC", nightMode: false,
                                        voice: id, createdAt: .now))
        }.get()
    }
}

enum VoiceFixtures {
    static let list = VoiceList(items: [
        Voice(id: "clint", name: "Clint", gender: .male, accent: "american", description: "Deep",
              previewURL: URL(string: "https://media.example.com/clint.mp3"), isDefault: true),
        Voice(id: "eve", name: "Eve", gender: .female, accent: "american", description: "Warm",
              previewURL: URL(string: "https://media.example.com/eve.mp3"), isDefault: false),
        Voice(id: "george", name: "George", gender: .male, accent: "british", description: "Storyteller",
              previewURL: URL(string: "https://media.example.com/george.mp3"), isDefault: false),
        Voice(id: "river", name: "River", gender: .neutral, accent: "american", description: "Calm",
              previewURL: nil, isDefault: false)
    ], defaultVoiceID: "clint")
}

@MainActor
struct VoicePickerTests {
    static let list = VoiceFixtures.list


    private func make(_ service: ScriptedVoices = ScriptedVoices(), appState: AppState = AppState(store: InMemoryPreferencesStore()))
    async -> (VoicePickerViewModel, FakePlayback, AppState) {
        let player = FakePlayback()
        let viewModel = VoicePickerViewModel(appState: appState, service: service, player: player)
        await viewModel.load()
        return (viewModel, player, appState)
    }

    @Test func aNewUserHasClintAndSettingsNamesIt() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        #expect(appState.voiceID == "clint")
        let settings = SettingsViewModel(appState: appState, purchases: MockPurchaseService(),
                                         account: MockAccountActions())
        #expect(settings.voiceName == "Clint")
        let (viewModel, _, _) = await make(appState: appState)
        #expect(viewModel.selectedID == "clint")
    }

    /// On the device, by gender; the neutral voice only under All.
    @Test func theFilterKeepsNeutralVoicesInAllOnly() async {
        let (viewModel, _, _) = await make()
        #expect(viewModel.visibleVoices.map(\.id) == ["clint", "eve", "george", "river"])
        viewModel.filter = .male
        #expect(viewModel.visibleVoices.map(\.id) == ["clint", "george"])
        viewModel.filter = .female
        #expect(viewModel.visibleVoices.map(\.id) == ["eve"])
    }

    @Test func onePreviewAtATimeAndListeningIsNotPicking() async {
        let (viewModel, player, _) = await make()
        viewModel.togglePreview(Self.list.items[0])
        viewModel.togglePreview(Self.list.items[1])
        #expect(player.loads.map(\.lastPathComponent) == ["clint.mp3", "eve.mp3"])
        #expect(viewModel.playingID == "eve")
        #expect(player.isPlaying)
        #expect(viewModel.selectedID == "clint")

        viewModel.togglePreview(Self.list.items[1])
        #expect(viewModel.playingID == nil)
        #expect(!player.isPlaying)
    }

    @Test func aPreviewNotReadyDoesNothingAndLeavingStopsSound() async {
        let (viewModel, player, _) = await make()
        viewModel.togglePreview(Self.list.items[3])
        #expect(player.loads.isEmpty && viewModel.playingID == nil)

        viewModel.togglePreview(Self.list.items[0])
        viewModel.stopPreview()
        #expect(!player.isPlaying && viewModel.playingID == nil)

        viewModel.togglePreview(Self.list.items[2])
        player.onEnd?()
        #expect(viewModel.playingID == nil)
    }

    @Test func aPickIsSavedAndNamedInSettings() async {
        let service = ScriptedVoices()
        let (viewModel, _, appState) = await make(service)
        await viewModel.select(Self.list.items[1])
        #expect(service.picks == ["eve"])
        #expect(viewModel.selectedID == "eve")
        #expect(appState.voiceID == "eve" && appState.voiceName == "Eve")
    }

    @Test func aFailedPickPutsTheCheckmarkBack() async {
        let service = ScriptedVoices(failure: .offline)
        let (viewModel, _, appState) = await make(service)
        await viewModel.select(Self.list.items[1])
        #expect(viewModel.selectedID == "clint")
        #expect(appState.voiceID == "clint")
        #expect(viewModel.toastMessage == "Couldn’t save your voice. Try again.")
        #expect(viewModel.haptic?.kind == .error)
        #expect(service.listCalls == 1)
    }

    /// The voice left the catalog while the screen was open: the list is asked again.
    @Test func anUnknownVoiceReloadsTheList() async {
        let service = ScriptedVoices(failure: .server(.init(code: .validationFailed, message: "voice", status: 400)))
        let (viewModel, _, _) = await make(service)
        await viewModel.select(Self.list.items[2])
        #expect(viewModel.selectedID == "clint")
        #expect(service.listCalls == 2)
    }

    @Test func thePickSurvivesARelaunch() async {
        let preferences = InMemoryPreferencesStore()
        let (viewModel, _, _) = await make(appState: AppState(store: preferences))
        await viewModel.select(Self.list.items[1])
        let relaunched = AppState(store: preferences)
        #expect(relaunched.voiceID == "eve")
        #expect(relaunched.voiceName == "Eve")
    }
}
