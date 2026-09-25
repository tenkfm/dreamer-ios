import Foundation
import Observation

/// Paged first-launch flow: 3 intro pages, 2 quiz questions, account, paywall.
/// The step follows the pager, so buttons and swipes go through the same `go(to:)`.
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable, Comparable, Hashable {
        case welcome, record, understand, quizGoal, quizLens, account, paywall

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Page dot index for the intro pages.
        var pageIndex: Int? {
            switch self {
            case .welcome: 0
            case .record: 1
            case .understand: 2
            default: nil
            }
        }

        var usesFullSky: Bool { self != .quizGoal && self != .quizLens }

        /// Name for `onboarding_step_viewed`.
        var analyticsName: String {
            switch self {
            case .welcome: "welcome"
            case .record: "record_intro"
            case .understand: "understand"
            case .quizGoal: "quiz_goal"
            case .quizLens: "quiz_lens"
            case .account: "account"
            case .paywall: "paywall"
            }
        }
    }

    private(set) var step: Step = .welcome
    var goal: Goal = .understand {
        didSet { if goal != oldValue { analytics.track(.quizAnswered(question: "goal", answer: goal.rawValue)) } }
    }
    var lens: Lens {
        didSet { if lens != oldValue { analytics.track(.quizAnswered(question: "lens", answer: lens.rawValue)) } }
    }
    /// "Welcome back" (from "I already have an account") or "Save your dreams".
    private(set) var accountMode: SignInViewModel.Mode = .signUp

    private let appState: AppState
    private let analytics: any Analytics

    init(appState: AppState, step: Step = .welcome, analytics: any Analytics = NoopAnalytics()) {
        self.appState = appState
        self.analytics = analytics
        lens = appState.preferredLens
        goal = appState.goal ?? .understand
        self.step = step
        // Someone who finished onboarding before and is signed out now comes back to sign in.
        if appState.onboardingCompleted && !appState.isSignedIn && step == .welcome {
            self.step = .account
            accountMode = .signIn
        }
        analytics.track(.onboardingStepViewed(step: self.step.analyticsName))
    }

    /// Pages the pager shows: nothing after the account step until there is an account, so a
    /// swipe cannot skip signing in.
    var reachableSteps: [Step] {
        appState.isSignedIn ? Step.allCases : Step.allCases.filter { $0 <= .account }
    }

    func go(to step: Step) {
        guard step != self.step, reachableSteps.contains(step) else { return }
        let previous = self.step
        self.step = step
        // Swipes also leave the quiz, so the answers are kept on the way forward.
        if previous <= .quizLens && step > .quizLens {
            appState.saveQuizAnswers(goal: goal, lens: lens)
        }
        analytics.track(.onboardingStepViewed(step: step.analyticsName))
    }

    func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        go(to: next)
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    /// "Skip" on the intro pages jumps to the quiz.
    func skipIntro() {
        go(to: .quizGoal)
    }

    /// "I already have an account": straight to sign-in.
    func useExistingAccount() {
        accountMode = .signIn
        go(to: .account)
    }

    /// A sign-in link from an email was opened: to the account step, which checks it.
    func openEmailLink() {
        if step != .account {
            accountMode = appState.onboardingCompleted ? .signIn : accountMode
            go(to: .account)
        }
    }

    /// Back from the account step: to the quiz for new users, to the start for returning ones.
    func leaveAccount() {
        go(to: accountMode == .signIn ? .welcome : .quizLens)
        accountMode = .signUp
    }

    /// Signed in on the account step. Returning users are done with onboarding (AppState moves them
    /// on). New users go on to the paywall - unless the backend gave them the `oneFree` variant,
    /// whose paywall comes after the first interpretation.
    func signedIn(_ session: AuthSession, subscription: SubscriptionInfo? = nil) {
        if let subscription { appState.serverSubscription = subscription }
        appState.signedIn(userID: session.userID, isNewUser: session.isNewUser)
        guard session.isNewUser else { return }
        if appState.hasFreeInterpretation {
            appState.finishOnboardingWithoutPurchase()
        } else {
            go(to: .paywall)
        }
    }
}
