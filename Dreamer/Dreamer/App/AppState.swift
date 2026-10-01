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
    var reminders: ReminderSettings {
        didSet {
            persist()
            syncReminderSettings(from: oldValue)
        }
    }
    /// The server's profile is being applied: nothing to send back.
    @ObservationIgnored private var applyingServerProfile = false
    /// The signed-in account; nil when signed out.
    private(set) var userID: String? { didSet { persist() } }

    // MARK: Navigation

    var selectedTab: AppTab = .today
    var paths: [AppTab: [Route]] = [:]
    var isRecordFlowPresented = false
    /// A told dream that was never read, to open straight in Analysis (from Journal or Home).
    var draftToRead: DreamDraft?
    /// A link the app was opened with, waiting for the screen that handles it (cold start included).
    var pendingDeepLink: DeepLink?
    /// Profile sync to run for the current account (set on sign-in and at launch).
    private(set) var pendingProfileSync: ProfileSyncDirection?
    /// When the free trial turns into the paid plan (nil: no renewing trial).
    private(set) var trialEndsAt: Date?
    /// The reminder pre-prompt was shown (once, on the first Home after onboarding).
    var reminderPromptShown: Bool { didSet { persist() } }
    /// Settings changed on this device and not yet on the server (kept across launches, so an
    /// offline change is not overwritten by the next pull).
    private(set) var unsyncedProfile: ProfileUpdate? { didSet { persist() } }
    /// A new value sends `unsyncedProfile` now.
    private(set) var profileWriteRequest: UUID?
    /// The backend's subscription record (paywall variant, free interpretations left).
    var serverSubscription: SubscriptionInfo? {
        didSet {
            guard let serverSubscription else { return }
            storedPaywallVariant = serverSubscription.paywallVariant
            freeInterpretationsLeft = serverSubscription.freeInterpretationsLeft
        }
    }
    private(set) var storedPaywallVariant: PaywallVariant? { didSet { persist() } }
    private(set) var freeInterpretationsLeft: Int { didSet { persist() } }
    /// "See plans" from anywhere in Main (record without access, Settings).
    var isPaywallSheetPresented = false
    /// Bumped to ask for a fresh backend subscription record; true = a purchase just happened.
    private(set) var subscriptionRefresh: SubscriptionRefreshRequest?

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
        storedPaywallVariant = saved.paywallVariant
        freeInterpretationsLeft = saved.freeInterpretationsLeft
        unsyncedProfile = saved.unsyncedProfile
        reminderPromptShown = saved.reminderPromptShown
    }

    /// Onboarding until the user has an account and has been through it (new users) or signed
    /// back in (returning users); then the hard paywall until there is a subscription.
    var rootScreen: RootScreen {
        guard isSignedIn, onboardingCompleted else { return .onboarding }
        if subscription == .none && !isPaywallBypassed && !hasFreeInterpretation { return .paywall }
        return .main
    }

    var isSignedIn: Bool { userID != nil }

    /// The paywall close button reaches Main only in Debug builds (testing); App Store builds keep
    /// the hard paywall.
    private var isPaywallBypassed: Bool {
        #if DEBUG
        paywallBypassed
        #else
        false
        #endif
    }

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
        pendingProfileSync = isNewUser ? .push : .pull
    }

    /// A restored session at launch refreshes the profile from the server.
    func requestProfilePull() {
        if isSignedIn { pendingProfileSync = .pull }
    }

    func profileSynced() {
        pendingProfileSync = nil
    }

    /// The main lens, from Settings or "Make this my main lens"; open interpretations follow it.
    func setPreferredLens(_ lens: Lens) {
        guard lens != preferredLens else { return }
        preferredLens = lens
        changeProfile(ProfileUpdate(preferredLens: lens))
    }

    /// Queues a setting for `/v1/me`. Before sign-in there is nothing to send: the onboarding push
    /// takes the whole local profile.
    func changeProfile(_ update: ProfileUpdate) {
        guard isSignedIn else { return }
        unsyncedProfile = (unsyncedProfile ?? ProfileUpdate()).merging(update)
        profileWriteRequest = UUID()
    }

    /// The backend has `sent`; a change made meanwhile stays queued.
    func profileUpdateSent(_ sent: ProfileUpdate) {
        if unsyncedProfile == sent { unsyncedProfile = nil }
    }

    /// The server's profile wins over the local copy (another device may have changed it).
    func apply(_ profile: UserProfile) {
        if let name = profile.name?.split(separator: " ").first.map(String.init) { userName = name }
        if let goal = profile.goal { self.goal = goal }
        preferredLens = profile.preferredLens
        var updated = reminders
        updated.morningReminder = profile.reminder.enabled
        let parts = profile.reminder.time.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 { updated.reminderMinutes = parts[0] * 60 + parts[1] }
        updated.nightModeAfter9 = profile.nightMode
        applyingServerProfile = true
        reminders = updated
        applyingServerProfile = false
    }

    /// Reminder, its time and night mode live in the profile too (`PATCH /v1/me`); the Face ID lock
    /// is this device's choice only.
    private func syncReminderSettings(from old: ReminderSettings) {
        guard !applyingServerProfile else { return }
        var update = ProfileUpdate()
        if old.morningReminder != reminders.morningReminder { update.reminderEnabled = reminders.morningReminder }
        if old.reminderMinutes != reminders.reminderMinutes {
            update.reminderTime = String(format: "%02d:%02d", reminders.reminderMinutes / 60, reminders.reminderMinutes % 60)
        }
        if old.nightModeAfter9 != reminders.nightModeAfter9 { update.nightMode = reminders.nightModeAfter9 }
        if update != ProfileUpdate() { changeProfile(update) }
    }

    /// The time zone changed (travel): the server's insights and reminders follow it.
    func timeZoneChanged(to zone: TimeZone = .current) {
        changeProfile(ProfileUpdate(timezone: zone.identifier))
    }

    /// The session ended (signed out, or the backend revoked it): back to sign-in, keeping the
    /// device's preferences.
    func signedOut() {
        userID = nil
        pendingProfileSync = nil
        unsyncedProfile = nil
        serverSubscription = nil
        storedPaywallVariant = nil
        freeInterpretationsLeft = 0
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
        requestSubscriptionRefresh(afterPurchase: true)
    }

    /// The store's word on access. Only for a signed-in account: purchases belong to it.
    func applyEntitlement(_ entitlement: EntitlementState) {
        guard isSignedIn else { return }
        // The paywall promises a reminder 2 days before a renewing trial turns paid.
        trialEndsAt = entitlement.isTrial && entitlement.willRenew ? entitlement.expiresAt : nil
        if entitlement.isPremium {
            let plan = entitlement.plan ?? subscription.plan ?? .yearly
            if subscription != .active(plan) { subscription = .active(plan) }
            onboardingCompleted = true
        } else if subscription != .none {
            // Expired, refunded or revoked: back to the paywall, no relaunch needed.
            subscription = .none
        }
    }

    func requestSubscriptionRefresh(afterPurchase: Bool) {
        subscriptionRefresh = SubscriptionRefreshRequest(afterPurchase: afterPurchase)
    }

    /// Paywall variant assigned by the backend at sign-up (hard until it says otherwise).
    var paywallVariant: PaywallVariant { serverSubscription?.paywallVariant ?? storedPaywallVariant ?? .hard }

    /// `oneFree` users read their first dream before the paywall.
    var hasFreeInterpretation: Bool { paywallVariant == .oneFree && freeInterpretationsLeft > 0 }

    /// Recording leads to an interpretation: it needs a subscription or a free one left.
    var canInterpret: Bool { subscription != .none || hasFreeInterpretation || isPaywallBypassed }

    /// A new `oneFree` account skips the onboarding paywall.
    func finishOnboardingWithoutPurchase() {
        onboardingCompleted = true
    }

    /// Debug builds: the paywall close button goes straight to Main (ignored in Release).
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
        unsyncedProfile = nil
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

    /// The mic: record when an interpretation can follow, otherwise the paywall first (a oneFree
    /// user who used the free one), so a told dream is never stuck behind a 402.
    func presentRecordFlow() {
        if canInterpret { isRecordFlowPresented = true } else { isPaywallSheetPresented = true }
    }

    /// Reads a waiting dream: Analysis on it, or the paywall when there is no plan (after buying,
    /// the draft queue sends it anyway).
    func readDraft(_ draft: DreamDraft) {
        guard canInterpret else { isPaywallSheetPresented = true; return }
        draftToRead = draft
        isRecordFlowPresented = true
    }

    /// A tapped notification: the morning reminder opens Record, a push about a dream opens it,
    /// the trial reminder opens Settings (the subscription row). Nothing before Main.
    func handle(_ link: NotificationLink) {
        guard rootScreen == .main else { return }
        switch link {
        case .record:
            if !isRecordFlowPresented { presentRecordFlow() }
        case .dream(let id):
            isRecordFlowPresented = false
            selectedTab = .journal
            paths[.journal] = [.interpretation(id)]
        case .subscription:
            selectedTab = .today
            paths[.today] = [.settings]
        }
    }

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
        preferences.paywallVariant = storedPaywallVariant
        preferences.freeInterpretationsLeft = freeInterpretationsLeft
        preferences.unsyncedProfile = unsyncedProfile
        preferences.reminderPromptShown = reminderPromptShown
        store.save(preferences)
    }
}

/// A request to reload the backend's subscription record; a new value re-runs the refresh.
struct SubscriptionRefreshRequest: Equatable, Sendable {
    let id = UUID()
    var afterPurchase: Bool
}
