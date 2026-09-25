import Foundation

/// Sign-out and account deletion: the server call, then everything the account left on the device.
@MainActor
protocol AccountActions: AnyObject {
    /// Always succeeds locally; the server logout is best effort (offline included).
    func signOut() async
    /// Server first: nothing is removed locally unless the backend deleted the account.
    func deleteAccount() async throws(APIError)
}

@MainActor
final class AccountController: AccountActions {
    private let auth: any AuthService
    private let dreamStore: any DreamStore
    private let appState: AppState
    /// SDK identities (RevenueCat, analytics, crash reports) and later the push token.
    private let unlink: @MainActor () async -> Void

    init(auth: any AuthService, dreamStore: any DreamStore, appState: AppState,
         unlink: @escaping @MainActor () async -> Void) {
        self.auth = auth
        self.dreamStore = dreamStore
        self.appState = appState
        self.unlink = unlink
    }

    func signOut() async {
        await auth.signOut()
        await clearDevice()
        // Preferences and quiz answers stay: the next sign-in on this iPhone is "Welcome back".
        appState.signedOut()
    }

    func deleteAccount() async throws(APIError) {
        // The backend deletes the data and files and revokes the Apple grant; the App Store
        // subscription is not touched (the user is told before confirming).
        try await auth.deleteAccount()
        await clearDevice()
        // Back to the state of a fresh install: Welcome, no quiz answers, default settings.
        appState.reset()
    }

    private func clearDevice() async {
        // Dreams of this account must not be readable by whoever signs in next.
        dreamStore.deleteAll()
        await unlink()
    }
}

/// For previews.
@MainActor
final class MockAccountActions: AccountActions {
    func signOut() async {}
    func deleteAccount() async throws(APIError) {}
}
