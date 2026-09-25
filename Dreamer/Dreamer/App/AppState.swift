import Foundation
import Observation

/// Session-level state: account, onboarding, preferences, subscription and navigation.
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
    /// The signed-in account; nil when signed out.
    private(set) var userID: String? { didSet { persist() } }

    // MARK: Navigation

    var selectedTab: AppTab = .today
    var paths: [AppTab: [Route]] = [:]
    var isRecordFlowPresented = false
    /// A link the app was opened with, waiting for the screen that handles it (cold start included).
    var pendingDeepLink: DeepLink?

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
        userID = saved.userID
    }

    /// Onboarding until the user has an account and has been through it (new users) or signed
    /// back in (returning users); then the hard paywall until there is a subscription.
    var rootScreen: RootScreen {
        guard isSignedIn, onboardingCompleted else { return .onboarding }
        if subscription == .none && !paywallBypassed { return .paywall }
        return .main
    }

    var isSignedIn: Bool { userID != nil }

    // MARK: Deep links

    func handle(_ link: DeepLink) {
        switch link {
        case .emailSignIn:
            // Already signed in: the link has nothing left to do (it was probably opened twice).
            guard !isSignedIn else { return }
            pendingDeepLink = link
        }
    }

    /// The handling screen takes the link (once).
    func consumeEmailSignInToken() -> String? {
        guard case .emailSignIn(let token) = pendingDeepLink else { return nil }
        pendingDeepLink = nil
        return token
    }

    // MARK: Account

    /// After a successful sign-in. A returning user skips the rest of onboarding.
    func signedIn(userID: String, isNewUser: Bool) {
        self.userID = userID
        if !isNewUser { onboardingCompleted = true }
    }

    /// The session ended (signed out, or the backend revoked it): back to sign-in, keeping the
    /// device's preferences.
    func signedOut() {
        userID = nil
        subscription = .none
        selectedTab = .today
        paths = [:]
        isRecordFlowPresented = false
    }

    /// Launch check: the Keychain is the truth about the session. Nil `storedUserID` means the
    /// tokens are gone (reinstall restores UserDefaults-free state, a revoked session...).
    func reconcileSession(storedUserID: String?) {
        if userID != storedUserID {
            if let storedUserID { userID = storedUserID } else { signedOut() }
        }
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

    /// Quiz answers, kept on the device until they are sent to the profile (IOS-02.5).
    func saveQuizAnswers(goal: Goal, lens: Lens) {
        self.goal = goal
        preferredLens = lens
    }

    func activateSubscription(_ plan: Plan) {
        subscription = .active(plan)
        onboardingCompleted = true
    }

    /// Phase 1: the paywall close button goes straight to Main.
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
        userID = nil
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
        var preferences = UserPreferences()
        preferences.onboardingCompleted = onboardingCompleted
        preferences.userName = userName
        preferences.goal = goal
        preferences.preferredLens = preferredLens
        preferences.subscription = subscription
        preferences.paywallBypassed = paywallBypassed
        preferences.reminders = reminders
        preferences.userID = userID
        store.save(preferences)
    }
}
