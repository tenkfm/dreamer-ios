#if DEBUG
import Foundation

/// Debug-only deep start for visual QA: `-debugScreen <name>` opens a screen directly
/// with in-memory preferences, e.g. `xcrun simctl launch booted com.braincode.dreamer.io -debugScreen journal`.
/// Add `-night` or `-day` to force the appearance regardless of the clock,
/// `-debugAdvance` to let the onboarding tap "Continue" once.
@MainActor
enum DebugLaunch {
    enum Screen: String {
        case welcome, recordIntro, understand, quizGoal, quizLens, account, paywall
        case home, journal, library, settings, deleteAccount, interpretation, symbol
        /// Interpretation of a crisis-flagged dream (the support screen).
        case support
        case record, details, analysis
    }

    static let screen: Screen? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-debugScreen"), index + 1 < arguments.count else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }()

    /// `-debugAdvance`: the onboarding taps "Continue" by itself every 2.5 s, up to the account step.
    static let autoAdvances = ProcessInfo.processInfo.arguments.contains("-debugAdvance")

    /// `-openLink <url>`: a link handed to the app at launch as if it had been opened, for a sign-in
    /// link the system will not route to this build (the server's AASA lists another app id).
    static let openLink: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-openLink"), index + 1 < arguments.count else { return nil }
        return URL(string: arguments[index + 1])
    }()

    /// `-night` / `-day`; nil follows the 9 PM schedule.
    static let forcedNightMode: Bool? = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-night") { return true }
        if arguments.contains("-day") { return false }
        return nil
    }()

    /// `-debugTime HH:mm`: today at that time for the greeting and day labels (store screenshots).
    static let clock: (() -> Date)? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-debugTime"), index + 1 < arguments.count else { return nil }
        let parts = arguments[index + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) ?? .now
        return { date }
    }()

    static var onboardingStep: OnboardingViewModel.Step? {
        switch screen {
        case .welcome: .welcome
        case .recordIntro: .record
        case .understand: .understand
        case .quizGoal: .quizGoal
        case .quizLens: .quizLens
        case .account: .account
        case .paywall: .paywall
        default: nil
        }
    }

    /// Prepares app state for the requested screen. Returns nil when no debug screen was asked for.
    static func makeAppState(dependencies: AppDependencies) -> AppState? {
        guard let screen else { return nil }
        var preferences = UserPreferences()
        preferences.userName = "Anna"
        let state = AppState(store: InMemoryPreferencesStore(preferences))
        if let forcedNightMode, forcedNightMode != state.isNightMode { state.toggleNightMode() }
        // Screenshots stay clean; `-askReminder` shows the reminder pre-prompt on Home.
        state.reminderPromptShown = !ProcessInfo.processInfo.arguments.contains("-askReminder")
        // `-lockJournal`: the journal lock is on (the simulator has no Face ID, so it stays locked).
        if ProcessInfo.processInfo.arguments.contains("-lockJournal") { state.reminders.lockWithFaceID = true }
        if screen == .paywall { state.signedIn(userID: "debug-user", isNewUser: true) }
        guard onboardingStep == nil else { return state }
        state.signedIn(userID: "debug-user", isNewUser: false)
        state.activateSubscription(.yearly)
        switch screen {
        case .journal: state.open(.journal)
        case .library: state.open(.library)
        case .settings, .deleteAccount: state.push(.settings, on: .today)
        case .interpretation:
            if let dream = dependencies.dreamStore.summaries.first { state.push(.interpretation(dream.id), on: .today) }
        case .support:
            if let id = dependencies.dreamStore.summaries.first?.id, var dream = dependencies.dreamStore.dream(id: id) {
                dream.interpretation?.safetyFlag = true
                dream.imageName = nil
                dependencies.dreamStore.save(dream)
                state.push(.interpretation(dream.id), on: .today)
            }
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
        flow.showDetails(for: .init(transcript: MockData.transcript))
        if screen == .analysis { flow.interpret(includeDetails: true) }
    }
}
#endif
