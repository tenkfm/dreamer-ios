import SwiftUI

/// First-launch flow over one panoramic sky that pans as the steps go by.
/// The intro pages and the quiz are one screen: the top bar and "Continue" stay, only the content
/// between them changes. The account step and the paywall are screens of their own and slide in
/// like a navigation push.
struct OnboardingFlowView: View {
    private typealias Step = OnboardingViewModel.Step

    @State private var viewModel: OnboardingViewModel
    /// The step on screen. It trails `viewModel.step` by one update, so the leaving content
    /// already carries the direction of the move when it is removed (a removal uses the transition
    /// the view had in its last update).
    @State private var shownStep: Step
    @State private var forward = true
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
        _shownStep = State(initialValue: viewModel.step)
    }

    var body: some View {
        ZStack {
            PanoramaSkyBackground.onboarding(at: shownStep)

            // One `if` per screen, each pushed in and out on its own. The zIndex keeps a leaving
            // screen above the sky: without it the ZStack draws it under the opaque background, and
            // it seems to vanish at once.
            Group {
                if shownStep.screen == .pages {
                    OnboardingPagesView(viewModel: viewModel, step: shownStep, forward: forward)
                        .transition(screenTransition)
                }
                if shownStep.screen == .account {
                    AccountStepView(viewModel: viewModel, dependencies: dependencies)
                        .transition(screenTransition)
                }
                if shownStep.screen == .paywall {
                    PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState,
                                                            placement: .onboarding, analytics: dependencies.analytics))
                        .transition(screenTransition)
                }
            }
            .zIndex(1)
        }
        .sensoryFeedback(.selection, trigger: viewModel.step)
        // A sign-in link can arrive on any step, while the account screen does not exist yet: go
        // there, and it takes the token when it appears.
        .onChange(of: appState.pendingDeepLink, initial: true) { _, link in
            if case .emailSignIn = link { viewModel.openEmailLink() }
        }
        .onChange(of: viewModel.step, initial: true) { old, step in
            guard step != shownStep else { return }
            forward = step > old
            Task { @MainActor in
                let target = viewModel.step
                let pushes = target.screen != shownStep.screen
                withAnimation(reduceMotion ? .default : pushes ? .push : .soft(0.7)) { shownStep = target }
            }
        }
        #if DEBUG
        .task {
            // `-debugAdvance`: taps "Continue" every 2.5 s up to the account step, to watch (or record)
            // every change without a finger.
            guard DebugLaunch.autoAdvances else { return }
            while viewModel.step < .account {
                try? await Task.sleep(for: .seconds(2.5))
                viewModel.next()
            }
        }
        #endif
    }

    /// A navigation push: the new screen comes in from the side of the move, the old one leaves to
    /// the other side.
    private var screenTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                           removal: .move(edge: forward ? .leading : .trailing))
    }
}

// MARK: - Account

/// The account step. Its view model is made with the view, not on appear: a placeholder frame
/// would slide in with the push before the form.
private struct AccountStepView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var signIn: SignInViewModel
    @Environment(AppState.self) private var appState

    init(viewModel: OnboardingViewModel, dependencies: AppDependencies) {
        self.viewModel = viewModel
        _signIn = State(initialValue: SignInViewModel(
            mode: viewModel.accountMode, auth: dependencies.auth, google: dependencies.googleSignIn,
            analytics: dependencies.analytics
        ) { session in
            Task {
                // The paywall variant decides where a new account goes next.
                let subscription = try? await dependencies.subscriptionStatus.subscription()
                viewModel.signedIn(session, subscription: subscription)
            }
        })
    }

    var body: some View {
        SignInView(viewModel: signIn) { viewModel.leaveAccount() }
            .onChange(of: viewModel.accountMode, initial: true) { _, mode in signIn.mode = mode }
            .onChange(of: appState.pendingDeepLink, initial: true) {
                guard let token = appState.consumeEmailSignInToken() else { return }
                viewModel.openEmailLink()
                Task { await signIn.verifyLink(token: token) }
            }
    }
}

// MARK: - Intro and quiz

/// The intro pages and the quiz on one frame: a top bar that morphs (logo and "Skip" on the intro,
/// Back and the quiz progress on the quiz), the page content, the page dots and the CTA.
private struct OnboardingPagesView: View {
    typealias Step = OnboardingViewModel.Step

    @Bindable var viewModel: OnboardingViewModel
    var step: Step
    var forward: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isQuiz: Bool { step == .quizGoal || step == .quizLens }
    private var introPageCount: Int { Step.allCases.filter { $0.pageIndex != nil }.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .id(step)
                .transition(contentTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)
            bottom
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HeaderBar(leading: {
            if isQuiz {
                GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { viewModel.back() }
                    .transition(.opacity)
            }
        }, center: {
            ZStack {
                if step == .record || step == .understand {
                    Logo().transition(.opacity)
                }
                if isQuiz {
                    quizProgress.transition(.opacity)
                }
            }
        }, trailing: {
            // Only on the second page: the third already leads straight to the quiz.
            if step == .record {
                SkyTextButton(title: "Skip") { viewModel.skipIntro() }
                    .transition(.opacity)
            }
        })
    }

    private var quizProgress: some View {
        let question = step == .quizGoal ? 1 : 2
        return HStack(spacing: 12) {
            // The bar repeats the label for the eye; VoiceOver reads the label only.
            ProgressCapsule(value: Double(question) / 2)
                .accessibilityHidden(true)
            Text("\(question) of 2")
                .font(DreamerFont.fixed(12))
                .foregroundStyle(DS.Palette.white)
                .skyTextShadow()
                .contentTransition(.numericText(value: Double(question)))
                .accessibilityLabel("Question \(question) of 2")
        }
        .padding(.leading, DS.Size.iconButton + 16)
        .padding(.trailing, DS.Size.iconButton + 8)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeContent { viewModel.next() }
        case .record: RecordIntroContent { viewModel.next() }
        case .understand: UnderstandContent()
        case .quizGoal: QuizGoalContent(viewModel: viewModel)
        case .quizLens: QuizLensContent(viewModel: viewModel)
        case .account, .paywall: EmptyView()
        }
    }

    /// The new content comes in from the side of the move and the old one leaves to the other,
    /// both fading, so the change reads as a step without the whole screen sliding.
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = 48
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? shift : -shift)),
            removal: .opacity.combined(with: .offset(x: forward ? -shift : shift))
        )
    }

    /// Swipes still page like the old pager did: left for the next step, right for the previous.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                if dx < 0 { viewModel.next() } else if step != .welcome { viewModel.back() }
            }
    }

    // MARK: Bottom

    private var bottom: some View {
        VStack(spacing: 0) {
            PageDots(count: introPageCount, position: CGFloat(step.pageIndex ?? introPageCount - 1))
                .opacity(isQuiz ? 0 : 1)
                .padding(.top, 20)
            VStack(spacing: 8) {
                PrimaryButton(title: ctaTitle) { viewModel.next() }
                // Kept in the quiz too, invisible, so "Continue" never moves between the steps.
                TextLinkButton(title: "I already have an account") { viewModel.useExistingAccount() }
                    .opacity(isQuiz ? 0 : 1)
                    .disabled(isQuiz)
                    .accessibilityHidden(isQuiz)
            }
            .padding(.top, 20)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, DS.Space.cta)
    }

    private var ctaTitle: String {
        switch step {
        case .welcome, .understand: String(localized: "Get started")
        default: String(localized: "Continue")
        }
    }
}

extension PanoramaSkyBackground {
    /// The onboarding sky as it stands at `step`. The paywall after sign-in keeps the account
    /// step's sky (here and as the root paywall), so signing in changes the screen, not the sky.
    static func onboarding(at step: OnboardingViewModel.Step) -> PanoramaSkyBackground {
        typealias Step = OnboardingViewModel.Step
        let skyStep = step == .paywall ? Step.account : step
        return PanoramaSkyBackground(
            image: .onboardingSky,
            progress: CGFloat(skyStep.rawValue) / CGFloat(Step.allCases.count - 1),
            pageCount: Step.allCases.count,
            topSkyAmount: skyStep.usesFullSky ? 0 : 1
        )
    }
}

private extension OnboardingViewModel.Step {
    enum Screen: Hashable { case pages, account, paywall }

    var screen: Screen {
        switch self {
        case .account: .account
        case .paywall: .paywall
        default: .pages
        }
    }
}

#Preview {
    let state = AppState.preview(onboardingCompleted: false)
    OnboardingFlowView(viewModel: OnboardingViewModel(appState: state))
        .environment(AppDependencies.preview())
        .environment(state)
}
