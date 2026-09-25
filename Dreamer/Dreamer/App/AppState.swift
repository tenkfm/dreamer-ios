import Foundation
import Observation

/// Session-level state: onboarding, preferences, subscription and navigation.
@MainActor
@Observable
final class AppState {
    enum RootScreen: Equatable { case onboarding, paywall, main }

    // MARK: Persisted

    private(set) var onboardingCompleted: Bool { didSet { persist() } }
    var userName: String { didSet { persist() } }
    var goal: Goal? { didSet { persist() } }
    var preferredLens: Lens { didSet { persist() } }
    private(set) var subscription: SubscriptionStatus { didSet { persist() } }
    private(set) var paywallBypassed: Bool { didSet { persist() } }
    var reminders: ReminderSettings { didSet { persist() } }

    // MARK: Navigation

    var selectedTab: AppTab = .today
    var paths: [AppTab: [Route]] = [:]
    var isRecordFlowPresented = false

    // MARK: Night mode

    /// Current time, refreshed by the root view so the schedule can switch while the app is open.
    private(set) var clock: Date
    /// Moon button choice. Holds until the schedule itself flips (at 9 PM or 5 AM).
    private(set) var nightModeOverride: Bool?

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let calendar: Calendar

    init(store: PreferencesStore, now: Date = .now, calendar: Calendar = .current) {
        self.store = store
        self.clock = now
        self.calendar = calendar
        let saved = store.load()
        onboardingCompleted = saved.onboardingCompleted
        userName = saved.userName
        goal = saved.goal
        preferredLens = saved.preferredLens
        subscription = saved.subscription
        paywallBypassed = saved.paywallBypassed
        reminders = saved.reminders
    }

    /// Hard paywall: onboarding done but no subscription shows the paywall before Main.
    var rootScreen: RootScreen {
        guard onboardingCompleted else { return .onboarding }
        if subscription == .none && !paywallBypassed { return .paywall }
        return .main
    }

    /// Night mode schedule: 9 PM to 5 AM, when "Night mode after 9 PM" is on.
    var isNightBySchedule: Bool {
        guard reminders.nightModeAfter9 else { return false }
        let hour = calendar.component(.hour, from: clock)
        return hour >= 21 || hour < 5
    }

    var isNightMode: Bool { nightModeOverride ?? isNightBySchedule }

    /// Moon button on Home.
    func toggleNightMode() {
        nightModeOverride = !isNightMode
    }

    /// Settings changed: follow the schedule again.
    func resetNightModeOverride() {
        nightModeOverride = nil
    }

    func refreshClock(_ now: Date = .now) {
        let wasNight = isNightBySchedule
        clock = now
        if isNightBySchedule != wasNight { nightModeOverride = nil }
    }

    // MARK: Onboarding & subscription

    func completeOnboarding(goal: Goal, lens: Lens) {
        self.goal = goal
        preferredLens = lens
    }

    func activateSubscription(_ plan: Plan) {
        subscription = .active(plan)
        onboardingCompleted = true
    }

    /// Phase 1: "I already have an account" and the paywall close button go straight to Main.
    func enterMainForTesting() {
        paywallBypassed = true
        onboardingCompleted = true
    }

    /// "Delete account and all dreams": back to a fresh install.
    func reset() {
        let fresh = UserPreferences()
        onboardingCompleted = fresh.onboardingCompleted
        userName = fresh.userName
        goal = fresh.goal
        preferredLens = fresh.preferredLens
        subscription = fresh.subscription
        paywallBypassed = fresh.paywallBypassed
        reminders = fresh.reminders
        nightModeOverride = nil
        selectedTab = .today
        paths = [:]
    }

    // MARK: Navigation

    func path(for tab: AppTab) -> [Route] { paths[tab, default: []] }

    func setPath(_ path: [Route], for tab: AppTab) { paths[tab] = path }

    func push(_ route: Route, on tab: AppTab) {
        paths[tab, default: []].append(route)
    }

    /// Switches tab and optionally opens a route on it.
    func open(_ tab: AppTab, route: Route? = nil) {
        selectedTab = tab
        if let route { push(route, on: tab) }
    }

    func presentRecordFlow() { isRecordFlowPresented = true }

    /// Record flow finished: the cover dismisses and the interpretation is pushed on Today,
    /// so Back returns to Home.
    func finishRecordFlow(with dreamID: Dream.ID) {
        isRecordFlowPresented = false
        selectedTab = .today
        paths[.today] = [.interpretation(dreamID)]
    }

    // MARK: Persistence

    private func persist() {
        store.save(UserPreferences(
            onboardingCompleted: onboardingCompleted,
            userName: userName,
            goal: goal,
            preferredLens: preferredLens,
            subscription: subscription,
            paywallBypassed: paywallBypassed,
            reminders: reminders
        ))
    }
}
