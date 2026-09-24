#if DEBUG
import Foundation

/// Debug-only deep start for visual QA: `-debugScreen <name>` opens a screen directly
/// with in-memory preferences, e.g. `xcrun simctl launch booted com.braincode.dreamer -debugScreen journal`.
@MainActor
enum DebugLaunch {
    enum Screen: String {
        case welcome, recordIntro, understand, quizGoal, quizLens, paywall
        case home, journal, library, settings, interpretation, symbol
        case record, details, analysis
    }

    static let screen: Screen? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-debugScreen"), index + 1 < arguments.count else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }()

    static var onboardingStep: OnboardingViewModel.Step? {
        switch screen {
        case .welcome: .welcome
        case .recordIntro: .record
        case .understand: .understand
        case .quizGoal: .quizGoal
        case .quizLens: .quizLens
        case .paywall: .paywall
        default: nil
        }
    }

    /// Prepares app state for the requested screen. Returns nil when no debug screen was asked for.
    static func makeAppState(dependencies: AppDependencies) -> AppState? {
        guard let screen else { return nil }
        let state = AppState(store: InMemoryPreferencesStore())
        guard onboardingStep == nil else { return state }
        state.activateSubscription(.yearly)
        switch screen {
        case .journal: state.open(.journal)
        case .library: state.open(.library)
        case .settings: state.push(.settings, on: .today)
        case .interpretation:
            if let dream = dependencies.dreamStore.dreams.first { state.push(.interpretation(dream.id), on: .today) }
        case .symbol: state.open(.library, route: .symbol(MockData.librarySymbols[0].id))
        case .record, .details, .analysis: state.presentRecordFlow()
        default: break
        }
        return state
    }

    /// Advances a freshly created record flow to the requested step.
    static func prepare(_ flow: RecordFlowViewModel) {
        guard screen == .details || screen == .analysis else { return }
        flow.record.transcript = MockData.transcript
        flow.finishRecording()
        if screen == .analysis { flow.interpret(includeDetails: true) }
    }
}
#endif
