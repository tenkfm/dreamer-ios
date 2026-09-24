import SwiftUI

/// Switches between onboarding, the hard paywall and the main app.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ZStack {
            switch appState.rootScreen {
            case .onboarding:
                OnboardingFlowView(viewModel: OnboardingViewModel(appState: appState, step: initialOnboardingStep))
                    .transition(.opacity)
            case .paywall:
                ZStack {
                    SkyBackground(kind: .full)
                    PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState))
                }
                .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.soft(0.6), value: appState.rootScreen)
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
