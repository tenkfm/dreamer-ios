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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.refreshClock() }
        }
        .task {
            // The backend ended the session (refresh refused): back to sign-in.
            guard let tokens = dependencies.tokens else { return }
            for await _ in tokens.signedOutEvents {
                appState.signedOut()
                dependencies.analytics.reset()
                dependencies.crashReporter.setUserID(nil)
            }
        }
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
