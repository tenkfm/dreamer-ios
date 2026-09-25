import Foundation

/// The backend's view of the subscription (`GET /v1/subscription`): it mirrors RevenueCat through
/// the webhook and also carries the paywall variant and the free interpretations left.
protocol SubscriptionStatusService: Sendable {
    func subscription() async throws(APIError) -> SubscriptionInfo
}

struct APISubscriptionStatusService: SubscriptionStatusService {
    let client: APIClient
    func subscription() async throws(APIError) -> SubscriptionInfo { try await client.subscription() }
}

struct MockSubscriptionStatusService: SubscriptionStatusService {
    var info = SubscriptionInfo(state: .active, isPremium: true, plan: .yearly, store: "appStore", expiresAt: nil,
                                willRenew: true, freeInterpretationsLeft: 0, paywallVariant: .hard)
    func subscription() async throws(APIError) -> SubscriptionInfo { info }
}

/// Access follows the store: the entitlement stream drives AppState (an expiry sends the user to
/// the paywall without a relaunch), and the backend's record is refreshed at launch and after a
/// purchase - when the webhook has not arrived yet it is polled for a few seconds (the backend asks
/// RevenueCat itself meanwhile).
@MainActor
struct SubscriptionSync {
    let appState: AppState
    let purchases: any PurchaseService
    let backend: any SubscriptionStatusService
    var pollInterval: Duration = .seconds(2)
    var maxPolls = 5

    /// Runs for the whole signed-in session.
    func followEntitlements() async {
        for await entitlement in purchases.entitlementUpdates() {
            appState.applyEntitlement(entitlement)
        }
    }

    /// `expectPremium`: right after a purchase, keep asking until the backend agrees.
    func refreshBackend(expectPremium: Bool) async {
        for attempt in 1...(expectPremium ? maxPolls : 1) {
            if let info = try? await backend.subscription() {
                appState.serverSubscription = info
                if !expectPremium || info.isPremium { return }
            }
            if attempt < maxPolls { try? await Task.sleep(for: pollInterval) }
        }
    }
}
