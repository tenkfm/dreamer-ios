import Foundation
import os
import Testing
@testable import Dreamer

/// Records the notes it receives; can fail on demand.
final class RecordingNotesService: DreamNotesService, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(saved: [String], failures: Int)>(initialState: ([], 0))
    var saved: [String] { state.withLock { $0.saved } }

    /// The next `count` calls fail offline.
    func failNext(_ count: Int) { state.withLock { $0.failures = count } }

    func saveNotes(_ notes: String, dreamID: UUID) async throws(APIError) {
        let fail = state.withLock { state -> Bool in
            if state.failures > 0 { state.failures -= 1; return true }
            state.saved.append(notes)
            return false
        }
        if fail { throw APIError.offline }
    }
}

/// Always refuses, like a server rejecting or unreachable.
private actor FailingProfileService: ProfileService {
    let error: APIError
    private(set) var calls = 0
    init(_ error: APIError) { self.error = error }
    func profile() async throws(APIError) -> UserProfile { calls += 1; throw error }
    func update(_ update: ProfileUpdate) async throws(APIError) -> UserProfile { calls += 1; throw error }
}

@MainActor
struct LensPromotionTests {
    private func makeViewModel(appState: AppState, analytics: any Analytics = NoopAnalytics(),
                               notes: (any DreamNotesService)? = nil) -> (InterpretationViewModel, InMemoryDreamStore) {
        let store = InMemoryDreamStore()
        let viewModel = InterpretationViewModel(dreamID: store.dreams[0].id, store: store, appState: appState,
                                                readAloud: MockReadAloudService(), imageSaver: MockImageSaver(),
                                                analytics: analytics, notesService: notes, notesDebounce: .milliseconds(20))
        return (viewModel, store)
    }

    private func signedInState(lens: Lens = .psychology) -> AppState {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.preferredLens = lens
        appState.signedIn(userID: "user-1", isNewUser: false)
        return appState
    }

    @Test func promotingMakesItTheAccountLensAndReportsIt() {
        let appState = signedInState()
        let analytics = RecordingAnalytics()
        let (viewModel, _) = makeViewModel(appState: appState, analytics: analytics)

        viewModel.promote(.spiritual)

        #expect(appState.preferredLens == .spiritual)
        #expect(appState.unsyncedProfile == ProfileUpdate(preferredLens: .spiritual))
        #expect(appState.profileWriteRequest != nil)
        #expect(analytics.events == [.lensPromoted(from: .psychology, to: .spiritual)])
    }

    @Test func aLensChangedInSettingsShowsOnAnOpenDream() {
        let appState = signedInState()
        let (viewModel, _) = makeViewModel(appState: appState)
        let settings = SettingsViewModel(appState: appState, purchases: MockPurchaseService(), account: MockAccountActions())

        settings.preferredLens = .dreamBook

        #expect(viewModel.mainLens == .dreamBook)
        #expect(viewModel.alternativeLenses == [.psychology, .spiritual])
        #expect(appState.unsyncedProfile?.preferredLens == .dreamBook)
    }

    @Test func beforeSignInNothingIsQueued() {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.setPreferredLens(.spiritual)
        #expect(appState.unsyncedProfile == nil)
    }

    @Test func unsyncedChangesSurviveARelaunch() {
        let preferences = InMemoryPreferencesStore()
        let appState = AppState(store: preferences)
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.setPreferredLens(.dreamBook)

        let relaunched = AppState(store: preferences)
        #expect(relaunched.unsyncedProfile == ProfileUpdate(preferredLens: .dreamBook))
    }
}

@MainActor
struct ProfileWriteTests {
    @Test func aQueuedChangeGoesUpAndIsCleared() async throws {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.setPreferredLens(.spiritual)
        let profiles = MockProfileService()

        await ProfileSync(appState: appState, profiles: profiles).sendPending()

        #expect(await profiles.updates == [ProfileUpdate(preferredLens: .spiritual)])
        #expect(appState.unsyncedProfile == nil)
    }

    @Test func anOfflineChangeIsSentBeforeThePullAndNotOverwritten() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.setPreferredLens(.dreamBook)
        // The server still has the old lens.
        let profiles = MockProfileService()

        await ProfileSync(appState: appState, profiles: profiles).run(.pull)

        #expect(appState.preferredLens == .dreamBook)
        #expect(await profiles.stored.preferredLens == .dreamBook)
    }

    @Test func offlineKeepsTheChangeAndSkipsThePull() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.setPreferredLens(.dreamBook)
        let profiles = FailingProfileService(.offline)

        await ProfileSync(appState: appState, profiles: profiles).run(.pull)

        #expect(appState.unsyncedProfile?.preferredLens == .dreamBook)
        #expect(await profiles.calls == 1)
    }

    @Test func aRefusedChangeIsDropped() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.setPreferredLens(.dreamBook)

        await ProfileSync(appState: appState, profiles: FailingProfileService(
            .server(.init(code: .validationFailed, message: "", status: 400)))).sendPending()

        #expect(appState.unsyncedProfile == nil)
    }

    @Test func laterChangesMergeOverEarlierOnes() {
        let merged = ProfileUpdate(preferredLens: .spiritual, nightMode: true)
            .merging(ProfileUpdate(preferredLens: .dreamBook))
        #expect(merged == ProfileUpdate(preferredLens: .dreamBook, nightMode: true))
    }
}

@MainActor
struct NotesSyncTests {
    private func makeViewModel(notes: RecordingNotesService) -> (InterpretationViewModel, InMemoryDreamStore) {
        let store = InMemoryDreamStore()
        let viewModel = InterpretationViewModel(dreamID: store.dreams[0].id, store: store,
                                                appState: AppState(store: InMemoryPreferencesStore()),
                                                readAloud: MockReadAloudService(), imageSaver: MockImageSaver(),
                                                notesService: notes, notesDebounce: .milliseconds(30))
        return (viewModel, store)
    }

    @Test func typingIsSavedOnceAfterAPause() async throws {
        let service = RecordingNotesService()
        let (viewModel, store) = makeViewModel(notes: service)

        viewModel.notes = "Stairs"
        viewModel.notes = "Stairs again"
        viewModel.notes = "Stairs again, like last week"
        #expect(store.dreams[0].notes == "Stairs again, like last week")
        #expect(service.saved.isEmpty)

        try await Task.sleep(for: .milliseconds(150))
        #expect(service.saved == ["Stairs again, like last week"])
    }

    @Test func leavingTheScreenSavesAtOnce() async {
        let service = RecordingNotesService()
        let (viewModel, _) = makeViewModel(notes: service)
        viewModel.notes = "Written just before leaving"

        await viewModel.flushNotes()

        #expect(service.saved == ["Written just before leaving"])
    }

    @Test func aFailedSaveIsTriedAgainOnLeaving() async throws {
        let service = RecordingNotesService()
        service.failNext(1)
        let (viewModel, _) = makeViewModel(notes: service)
        viewModel.notes = "Offline thought"
        try await Task.sleep(for: .milliseconds(150))
        #expect(service.saved.isEmpty)

        await viewModel.flushNotes()
        #expect(service.saved == ["Offline thought"])
    }

    @Test func notesStopAtTheBackendLimit() {
        let (viewModel, store) = makeViewModel(notes: RecordingNotesService())
        viewModel.notes = String(repeating: "a", count: InterpretationViewModel.notesLimit + 20)
        #expect(viewModel.notes.count == InterpretationViewModel.notesLimit)
        #expect(store.dreams[0].notes.count == InterpretationViewModel.notesLimit)
    }
}
