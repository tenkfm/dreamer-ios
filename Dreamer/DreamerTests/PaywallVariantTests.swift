import Foundation
import Testing
@testable import Dreamer

@MainActor
struct PaywallVariantTests {
    private func info(_ variant: PaywallVariant, freeLeft: Int, premium: Bool = false) -> SubscriptionInfo {
        SubscriptionInfo(state: premium ? .active : .none, isPremium: premium, plan: nil, store: nil, expiresAt: nil,
                         willRenew: false, freeInterpretationsLeft: freeLeft, paywallVariant: variant)
    }

    private func newSession() -> AuthSession {
        AuthSession(accessToken: "a", accessExpiresAt: .now, refreshToken: "r", refreshExpiresAt: .now, userID: "u1", isNewUser: true)
    }

    @Test func hardVariantShowsThePaywallRightAfterSignUp() {
        let appState = AppState(store: InMemoryPreferencesStore())
        let onboarding = OnboardingViewModel(appState: appState, step: .account)
        onboarding.signedIn(newSession(), subscription: info(.hard, freeLeft: 0))

        #expect(onboarding.step == .paywall)
        #expect(appState.rootScreen == .onboarding)
    }

    @Test func oneFreeVariantSkipsThePaywallUntilTheFreeDreamIsUsed() {
        let store = InMemoryPreferencesStore()
        let appState = AppState(store: store)
        let onboarding = OnboardingViewModel(appState: appState, step: .account)
        onboarding.signedIn(newSession(), subscription: info(.oneFree, freeLeft: 1))

        #expect(appState.rootScreen == .main)
        #expect(appState.canInterpret)

        // Known before the backend answers again on the next launch.
        #expect(AppState(store: store).rootScreen == .main)

        appState.serverSubscription = info(.oneFree, freeLeft: 0)
        #expect(appState.rootScreen == .paywall)
        #expect(!appState.canInterpret)
    }

    @Test func micWithoutAccessOpensThePaywallInsteadOfRecording() {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "u1", isNewUser: false)
        appState.serverSubscription = info(.oneFree, freeLeft: 0)

        appState.presentRecordFlow()

        #expect(!appState.isRecordFlowPresented)
        #expect(appState.isPaywallSheetPresented)
    }

    @Test func paywallEventsFollowTheTrackingPlan() async {
        let analytics = RecordingAnalytics()
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.serverSubscription = info(.oneFree, freeLeft: 0)
        let viewModel = PaywallViewModel(purchases: MockPurchaseService(delay: .zero), appState: appState,
                                         placement: .record, analytics: analytics)
        await viewModel.loadProducts()

        viewModel.viewed()
        viewModel.viewed()
        viewModel.select(.weekly)
        viewModel.select(.weekly)
        await viewModel.purchase()

        #expect(analytics.events == [
            // Record shows the paywall because the free interpretation is used up.
            .paywallViewed(placement: .limit, variant: "oneFree"),
            .planSelected(plan: .weekly),
            .purchaseStarted(plan: .weekly)
        ])
    }

    @Test func subscriberManagesTheSubscriptionInsteadOfSeeingPlans() {
        let appState = AppState.preview()
        let settings = SettingsViewModel(appState: appState, purchases: MockPurchaseService(), account: MockAccountActions())
        settings.openSubscription()
        #expect(settings.isManagingSubscription)
        #expect(settings.activeSheet == nil)

        let free = AppState(store: InMemoryPreferencesStore())
        let freeSettings = SettingsViewModel(appState: free, purchases: MockPurchaseService(), account: MockAccountActions())
        freeSettings.openSubscription()
        #expect(freeSettings.activeSheet == .subscription)
    }

    @Test func restoreWithoutPurchasesExplainsIt() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "u1", isNewUser: true)
        let viewModel = PaywallViewModel(purchases: MockPurchaseService(delay: .zero, restoredPlan: nil), appState: appState)
        await viewModel.restore()
        #expect(viewModel.alertMessage == "We couldn’t find a previous purchase.")
        #expect(viewModel.haptic?.kind == .warning)
        #expect(appState.subscription == .none)
    }
}
