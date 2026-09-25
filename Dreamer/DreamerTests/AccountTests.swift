import Foundation
import Testing
@testable import Dreamer

@MainActor
struct AccountControllerTests {
    private func signedInState() -> AppState {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.saveQuizAnswers(goal: .recurring, lens: .spiritual)
        appState.signedIn(userID: "user-1", isNewUser: true)
        appState.activateSubscription(.yearly)
        return appState
    }

    private func liveAuth(handler: @escaping StubURLProtocol.Handler) async -> (APIAuthService, TokenManager, host: String) {
        let store = InMemorySecureStore()
        let tokens = TokenManager(store: store) { _ throws(APIError) in throw .signedOut }
        await tokens.start(AuthSession(accessToken: "acc", accessExpiresAt: .now.addingTimeInterval(900), refreshToken: "ref",
                                       refreshExpiresAt: .now.addingTimeInterval(86_400), userID: "user-1", isNewUser: false))
        let (client, host) = StubURLProtocol.makeClient(tokens: tokens, handler: handler)
        return (APIAuthService(client: client, tokens: tokens), tokens, host)
    }

    @Test func deletionCallsTheAPIThenResetsTheDevice() async throws {
        let (auth, tokens, host) = await liveAuth { _ in .empty(204) }
        let appState = signedInState()
        let dreams = InMemoryDreamStore()
        var unlinked = false
        let account = AccountController(auth: auth, dreamStore: dreams, appState: appState) { unlinked = true }

        try await account.deleteAccount()

        let request = try #require(StubURLProtocol.requests(for: host).first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path() == "/v1/me")
        #expect(await tokens.isSignedIn == false)
        #expect(dreams.dreams.isEmpty)
        #expect(unlinked)
        #expect(appState.rootScreen == .onboarding)
        #expect(appState.onboardingCompleted == false)
        #expect(appState.goal == nil)
    }

    @Test func failedDeletionKeepsEverything() async {
        let (auth, tokens, _) = await liveAuth { _ in .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet)) }
        let appState = signedInState()
        let dreams = InMemoryDreamStore()
        let viewModel = SettingsViewModel(appState: appState, purchases: MockPurchaseService(),
                                          account: AccountController(auth: auth, dreamStore: dreams, appState: appState) {})

        await viewModel.deleteAccount()

        #expect(viewModel.deleteError?.kind == .offline)
        #expect(await tokens.isSignedIn)
        #expect(!dreams.dreams.isEmpty)
        #expect(appState.rootScreen == .main)
    }

    @Test func signOutEndsTheSessionButKeepsThePreferences() async throws {
        let (auth, tokens, host) = await liveAuth { _ in .empty(204) }
        let appState = signedInState()
        let dreams = InMemoryDreamStore()
        let account = AccountController(auth: auth, dreamStore: dreams, appState: appState) {}

        await account.signOut()

        let request = try #require(StubURLProtocol.requests(for: host).first)
        #expect(request.url?.path() == "/v1/auth/logout")
        #expect(await tokens.isSignedIn == false)
        #expect(dreams.dreams.isEmpty)
        #expect(appState.rootScreen == .onboarding)
        #expect(appState.preferredLens == .spiritual)
        #expect(OnboardingViewModel(appState: appState).accountMode == .signIn)
    }

    @Test func signOutWorksOffline() async {
        let (auth, tokens, _) = await liveAuth { _ in .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet)) }
        let appState = signedInState()
        await AccountController(auth: auth, dreamStore: InMemoryDreamStore(), appState: appState) {}.signOut()

        #expect(await tokens.isSignedIn == false)
        #expect(!appState.isSignedIn)
    }
}
