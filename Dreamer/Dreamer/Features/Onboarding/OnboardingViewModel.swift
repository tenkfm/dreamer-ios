import Foundation
import Observation

/// Paged first-launch flow: 3 intro pages, 2 quiz questions, paywall.
/// The step follows the pager, so buttons and swipes go through the same `go(to:)`.
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable, Comparable, Hashable {
        case welcome, record, understand, quizGoal, quizLens, paywall

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
    }

    private(set) var step: Step = .welcome
    var goal: Goal = .understand
    var lens: Lens

    private let appState: AppState

    init(appState: AppState, step: Step = .welcome) {
        self.appState = appState
        self.step = step
        lens = appState.preferredLens
        goal = appState.goal ?? .understand
    }

    func go(to step: Step) {
        guard step != self.step else { return }
        self.step = step
        // The paywall can be reached by swiping too, so the answers are committed on arrival.
        if step == .paywall {
            appState.completeOnboarding(goal: goal, lens: lens)
        }
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

    /// Phase 1: "I already have an account" opens Main directly.
    func useExistingAccount() {
        appState.enterMainForTesting()
    }
}
