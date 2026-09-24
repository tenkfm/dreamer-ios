import SwiftUI

/// Hosts the onboarding steps over a still sky; content crossfades and slides between steps.
struct OnboardingFlowView: View {
    @State private var viewModel: OnboardingViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: .full)
                .opacity(viewModel.step.usesFullSky ? 1 : 0)
            SkyBackground(kind: .top)
                .opacity(viewModel.step.usesFullSky ? 0 : 1)

            content
                .id(viewModel.step)
                .transition(.stepChange)
        }
        .animation(.soft(0.6), value: viewModel.step)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.step {
        case .welcome:
            WelcomePage(onContinue: viewModel.next, onExistingAccount: viewModel.useExistingAccount)
        case .record:
            RecordIntroPage(onContinue: viewModel.next, onSkip: viewModel.skipIntro,
                            onExistingAccount: viewModel.useExistingAccount)
        case .understand:
            UnderstandPage(onContinue: viewModel.next, onSkip: viewModel.skipIntro,
                           onExistingAccount: viewModel.useExistingAccount)
        case .quizGoal:
            QuizGoalView(viewModel: viewModel)
        case .quizLens:
            QuizLensView(viewModel: viewModel)
        case .paywall:
            PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState))
        }
    }
}

#Preview {
    let state = AppState.preview(onboardingCompleted: false)
    OnboardingFlowView(viewModel: OnboardingViewModel(appState: state))
        .environment(AppDependencies.preview())
        .environment(state)
}
