import SwiftUI

/// Onboarding as a horizontal pager: swipe or tap through the steps while one panoramic sky
/// moves behind all pages. Each page plays its entrance when it first slides into view.
struct OnboardingFlowView: View {
    private typealias Step = OnboardingViewModel.Step

    @State private var viewModel: OnboardingViewModel
    /// Continuous pager position in pages (1.5 = halfway between the 2nd and 3rd page).
    @State private var pagePosition: CGFloat = 0
    /// Pages that have been on screen; their entrance animations may play.
    @State private var revealedSteps: Set<Step> = []
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
        _pagePosition = State(initialValue: CGFloat(viewModel.step.rawValue))
        _revealedSteps = State(initialValue: [viewModel.step])
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

                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        // Eager (not lazy) so every page has its exact frame from the first layout:
                        // the pager always starts on the bound step and button taps slide precisely.
                        HStack(spacing: 0) {
                            ForEach(viewModel.reachableSteps, id: \.self) { step in
                                page(for: step)
                                    .containerRelativeFrame(.horizontal)
                                    .environment(\.entranceActive, revealedSteps.contains(step))
                                    .id(step)
                            }
                        }
                        .scrollTargetLayout()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            -proxy.frame(in: .scrollView).minX
                        } action: { offset in
                            updatePosition(offset / max(geo.size.width, 1))
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: stepBinding)
                    .scrollIndicators(.hidden)
                    // Layout stays inside the safe area, but shadows may spill into it.
                    .scrollClipDisabled()
                    // An appearance switch (night mode at 9 PM) can reset the offset without
                    // touching the bound step, so the pager is re-pinned to it.
                    .onAppear { reader.scrollTo(viewModel.step) }
                    .onChange(of: colorScheme) { reader.scrollTo(viewModel.step) }
                }
            }
        }
        .overlayPreferenceValue(PageDotsSlotKey.self) { slots in
            GeometryReader { proxy in
                if let point = dotsPoint(in: proxy, slots: slots) {
                    PageDots(count: introPageCount, position: pagePosition)
                        .position(x: proxy.size.width / 2, y: point.y)
                        // Fades out as the quiz slides in.
                        .opacity(Double(min(max(CGFloat(introPageCount) - pagePosition, 0), 1)))
                        .enterUp(0.7)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.step)
        .trackScreen(.onboarding)
        .onChange(of: viewModel.step, initial: true) { _, step in
            // Placement A of the tracking question: right before the paywall.
            if step == .paywall { dependencies.trackingConsent.moment(.onboardingPaywall) }
        }
        #if DEBUG
        .task {
            // `-debugAdvance`: taps "Continue" after 2 s, to check the slide without a finger.
            guard DebugLaunch.autoAdvances else { return }
            try? await Task.sleep(for: .seconds(2))
            next()
        }
        #endif
    }

    // MARK: Pages

    @ViewBuilder private func page(for step: Step) -> some View {
        switch step {
        case .welcome:
            WelcomePage(onContinue: next, onExistingAccount: existingAccount)
        case .record:
            RecordIntroPage(onContinue: next, onSkip: skip, onExistingAccount: existingAccount)
        case .understand:
            UnderstandPage(onContinue: next, onSkip: skip, onExistingAccount: existingAccount)
        case .quizGoal:
            QuizGoalView(viewModel: viewModel, onBack: back, onContinue: next)
        case .quizLens:
            QuizLensView(viewModel: viewModel, onBack: back, onContinue: next)
        case .account:
            ViewModelHost {
                SignInViewModel(mode: viewModel.accountMode, auth: dependencies.auth, analytics: dependencies.analytics) { session in
                    Task {
                        // The paywall variant decides where a new account goes next.
                        let subscription = try? await dependencies.subscriptionStatus.subscription()
                        withAnimation(.soft(0.6)) { viewModel.signedIn(session, subscription: subscription) }
                    }
                }
            } content: { signIn in
                SignInView(viewModel: signIn) {
                    withAnimation(.soft(0.8)) { viewModel.leaveAccount() }
                }
                .onChange(of: viewModel.accountMode, initial: true) { _, mode in signIn.mode = mode }
                .onChange(of: appState.pendingDeepLink, initial: true) {
                    guard let token = appState.consumeEmailSignInToken() else { return }
                    withAnimation(.soft(0.8)) { viewModel.openEmailLink() }
                    Task { await signIn.verifyLink(token: token) }
                }
            }
        case .paywall:
            PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState,
                                                    placement: .onboarding, analytics: dependencies.analytics))
        }
    }

    // MARK: Paging

    /// The pager and the view model share one step; button taps animate the scroll.
    private var stepBinding: Binding<Step?> {
        Binding(get: { viewModel.step },
                set: { if let step = $0 { viewModel.go(to: step) } })
    }

    private var introPageCount: Int { Step.allCases.filter { $0.pageIndex != nil }.count }

    /// Where the shared dots sit: the slot of the intro page nearest to the pager position.
    private func dotsPoint(in proxy: GeometryProxy, slots: [Int: Anchor<CGPoint>]) -> CGPoint? {
        let nearest = min(max(Int(pagePosition.rounded()), 0), introPageCount - 1)
        guard let anchor = slots[nearest] ?? slots.values.first else { return nil }
        return proxy[anchor]
    }

    /// Tracks the continuous position for the sky and reveals a page as soon as it slides in.
    private func updatePosition(_ position: CGFloat) {
        pagePosition = position
        for step in Step.allCases where abs(CGFloat(step.rawValue) - position) < 1 {
            if !revealedSteps.contains(step) { revealedSteps.insert(step) }
        }
    }

    private func next() { withAnimation(.soft(0.6)) { viewModel.next() } }
    private func back() { withAnimation(.soft(0.6)) { viewModel.back() } }
    private func skip() { withAnimation(.soft(0.8)) { viewModel.skipIntro() } }
    private func existingAccount() { withAnimation(.soft(0.9)) { viewModel.useExistingAccount() } }

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
