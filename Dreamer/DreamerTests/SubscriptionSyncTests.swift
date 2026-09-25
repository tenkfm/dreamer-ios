import Foundation
import os
import Testing
@testable import Dreamer

@MainActor
struct SubscriptionSyncTests {
    /// Emits the given entitlements, then ends.
    struct ScriptedStore: PurchaseService {
        var updates: [EntitlementState]
        func products() async throws -> [PaywallProduct] { [] }
        func purchase(_ plan: Plan) async throws -> PurchaseOutcome { .cancelled }
        func restore() async throws -> EntitlementState { .none }
        func entitlementUpdates() -> AsyncStream<EntitlementState> {
            AsyncStream { continuation in
                for update in updates { continuation.yield(update) }
                continuation.finish()
            }
        }
        func logIn(userID: String) async {}
        func logOut() async {}
    }

    /// Answers `isPremium: false` until the n-th call.
    final class SlowWebhookBackend: SubscriptionStatusService {
        private let calls = OSAllocatedUnfairLock(initialState: 0)
        let premiumFromCall: Int
        init(premiumFromCall: Int) { self.premiumFromCall = premiumFromCall }
        var count: Int { calls.withLock { $0 } }

        func subscription() async throws(APIError) -> SubscriptionInfo {
            let n = calls.withLock { $0 += 1; return $0 }
            return SubscriptionInfo(state: n >= premiumFromCall ? .trialing : .none, isPremium: n >= premiumFromCall,
                                    plan: .yearly, store: "appStore", expiresAt: nil, willRenew: true,
                                    freeInterpretationsLeft: 0, paywallVariant: .oneFree)
        }
    }

    private func signedIn() -> AppState {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: true)
        return appState
    }

    @Test func expiryInTheStoreShowsThePaywallWithoutARelaunch() async {
        let appState = signedIn()
        let active = EntitlementState(isPremium: true, plan: .weekly, expiresAt: nil, willRenew: true)
        let sync = SubscriptionSync(appState: appState, purchases: ScriptedStore(updates: [active, .none]),
                                    backend: MockSubscriptionStatusService())

        await sync.followEntitlements()

        #expect(appState.subscription == .none)
        #expect(appState.rootScreen == .paywall)
    }

    @Test func activeEntitlementUnlocksMain() async {
        let appState = signedIn()
        let active = EntitlementState(isPremium: true, plan: .yearly, expiresAt: nil, willRenew: true)
        await SubscriptionSync(appState: appState, purchases: ScriptedStore(updates: [active]),
                               backend: MockSubscriptionStatusService()).followEntitlements()

        #expect(appState.subscription == .active(.yearly))
        #expect(appState.rootScreen == .main)
    }

    @Test func entitlementsBeforeSignInAreIgnored() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        let active = EntitlementState(isPremium: true, plan: .yearly, expiresAt: nil, willRenew: true)
        await SubscriptionSync(appState: appState, purchases: ScriptedStore(updates: [active]),
                               backend: MockSubscriptionStatusService()).followEntitlements()
        #expect(appState.subscription == .none)
    }

    @Test func afterAPurchaseTheBackendIsPolledUntilItAgrees() async {
        let appState = signedIn()
        let backend = SlowWebhookBackend(premiumFromCall: 3)
        let sync = SubscriptionSync(appState: appState, purchases: ScriptedStore(updates: []), backend: backend,
                                    pollInterval: .milliseconds(1))

        await sync.refreshBackend(expectPremium: true)

        #expect(backend.count == 3)
        #expect(appState.serverSubscription?.isPremium == true)
        #expect(appState.paywallVariant == .oneFree)
    }

    @Test func launchRefreshAsksOnce() async {
        let appState = signedIn()
        let backend = SlowWebhookBackend(premiumFromCall: 10)
        await SubscriptionSync(appState: appState, purchases: ScriptedStore(updates: []), backend: backend,
                               pollInterval: .milliseconds(1)).refreshBackend(expectPremium: false)
        #expect(backend.count == 1)
    }

    @Test func premiumRequiredAnalysisCanBeResumedAfterBuying() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(402, #"{"error":{"code":"PREMIUM_REQUIRED","message":"Subscribe"}}"#)
        }
        let viewModel = AnalysisViewModel(draft: DreamDraft(transcript: "A dream"),
                                          service: APIDreamAnalysisService(client: client), store: InMemoryDreamStore(seed: []))
        await viewModel.run()

        #expect(viewModel.errorState?.action == .openPaywall)
        #expect(!viewModel.canRetry)
    }
}
