import SwiftUI

/// Onboarding as a horizontal pager: swipe or tap through the steps while one panoramic sky
/// moves behind all pages.
struct OnboardingFlowView: View {
    private typealias Step = OnboardingViewModel.Step

    @State private var viewModel: OnboardingViewModel
    /// Continuous pager position in pages (1.5 = halfway between the 2nd and 3rd page).
    @State private var pagePosition: CGFloat = 0
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
        _pagePosition = State(initialValue: CGFloat(viewModel.step.rawValue))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PanoramaSkyBackground(
                    image: .onboardingSky,
                    progress: pagePosition / CGFloat(Step.allCases.count - 1),
                    pageCount: Step.allCases.count,
                    topSkyAmount: topSkyAmount
                )

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Step.allCases, id: \.self) { step in
                            page(for: step)
                                .containerRelativeFrame(.horizontal)
                                .id(step)
                        }
                    }
                    .scrollTargetLayout()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        -proxy.frame(in: .scrollView).minX
                    } action: { offset in
                        pagePosition = offset / max(geo.size.width, 1)
                    }
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: stepBinding)
                .scrollIndicators(.hidden)
                .scrollEdgeEffectsHidden()
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.step)
    }

    // MARK: Pages

    @ViewBuilder private func page(for step: Step) -> some View {
        switch step {
        case .welcome:
            WelcomePage(onContinue: next, onExistingAccount: viewModel.useExistingAccount)
        case .record:
            RecordIntroPage(onContinue: next, onSkip: skip, onExistingAccount: viewModel.useExistingAccount)
        case .understand:
            UnderstandPage(onContinue: next, onSkip: skip, onExistingAccount: viewModel.useExistingAccount)
        case .quizGoal:
            QuizGoalView(viewModel: viewModel, onBack: back, onContinue: next)
        case .quizLens:
            QuizLensView(viewModel: viewModel, onBack: back, onContinue: next)
        case .paywall:
            PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState))
        }
    }

    // MARK: Paging

    /// The pager and the view model share one step; button taps animate the scroll.
    private var stepBinding: Binding<Step?> {
        Binding(get: { viewModel.step },
                set: { if let step = $0 { viewModel.go(to: step) } })
    }

    private func next() { withAnimation(.soft(0.6)) { viewModel.next() } }
    private func back() { withAnimation(.soft(0.6)) { viewModel.back() } }
    private func skip() { withAnimation(.soft(0.8)) { viewModel.skipIntro() } }

    /// Blends the quiz "sky only at the top" look in and out as the pages slide.
    private var topSkyAmount: Double {
        let steps = Step.allCases
        let clamped = min(max(pagePosition, 0), CGFloat(steps.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, steps.count - 1)
        let fraction = Double(clamped - CGFloat(lower))
        let value = { (step: Step) in step.usesFullSky ? 0.0 : 1.0 }
        return value(steps[lower]) * (1 - fraction) + value(steps[upper]) * fraction
    }
}

#Preview {
    let state = AppState.preview(onboardingCompleted: false)
    OnboardingFlowView(viewModel: OnboardingViewModel(appState: state))
        .environment(AppDependencies.preview())
        .environment(state)
}
