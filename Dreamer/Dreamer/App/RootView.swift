import SwiftUI

/// Switches between onboarding, the hard paywall and the main app.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch appState.rootScreen {
            case .onboarding:
                OnboardingFlowView(viewModel: OnboardingViewModel(appState: appState, step: initialOnboardingStep,
                                                                  analytics: dependencies.analytics))
                    .offlineBannerInset()
                    .transition(.opacity)
            case .paywall:
                ZStack {
                    SkyBackground(kind: .full)
                    PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState))
                        .offlineBannerInset()
                }
                .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.soft(0.6), value: appState.rootScreen)
        // The app always sets its own appearance: night mode, never the system setting.
        .preferredColorScheme(appState.isNightMode ? .dark : .light)
        // Screens draw clear sky under their headers; no iOS 26 blur at scroll edges anywhere.
        .scrollEdgeEffectsHidden()
        .task {
            // Lets the 9 PM / 5 AM schedule switch while the app stays open.
            while !Task.isCancelled {
                appState.refreshClock()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Universal links arrive here at a cold start and while the app runs.
        .onOpenURL { url in
            if let link = DeepLink(url: url, apiHost: AppConfig.current.apiBaseURL?.host()) {
                appState.handle(link)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.refreshClock() }
        }
        .task(id: appState.userID) {
            // Every sign-in (and a session restored at launch) links the account in the SDKs.
            if let userID = appState.userID { await dependencies.linkAccount(userID: userID) }
        }
        .task(id: appState.userID) {
            // Store access for the whole session: renewals, expiries and refunds apply at once.
            guard appState.isSignedIn else { return }
            appState.requestSubscriptionRefresh(afterPurchase: false)
            await subscriptionSync.followEntitlements()
        }
        .task(id: appState.subscriptionRefresh) {
            guard let request = appState.subscriptionRefresh, appState.isSignedIn else { return }
            await subscriptionSync.refreshBackend(expectPremium: request.afterPurchase)
        }
        .task(id: appState.pendingProfileSync) {
            // New account: quiz answers and settings go up; existing one: the server's profile comes down.
            guard let direction = appState.pendingProfileSync else { return }
            await ProfileSync(appState: appState, profiles: dependencies.profiles).run(direction)
        }
        .task {
            // The backend ended the session (refresh refused): back to sign-in.
            guard let tokens = dependencies.tokens else { return }
            for await _ in tokens.signedOutEvents {
                appState.signedOut()
                await dependencies.unlinkAccount()
            }
        }
    }

    private var subscriptionSync: SubscriptionSync {
        SubscriptionSync(appState: appState, purchases: dependencies.purchases, backend: dependencies.subscriptionStatus)
    }

    private var initialOnboardingStep: OnboardingViewModel.Step {
        #if DEBUG
        DebugLaunch.onboardingStep ?? .welcome
        #else
        .welcome
        #endif
    }
}

#Preview {
    RootView()
        .environment(AppDependencies.preview())
        .environment(AppState.preview(onboardingCompleted: false))
}
