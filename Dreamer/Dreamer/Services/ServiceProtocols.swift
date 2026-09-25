import Foundation

// Service boundaries. Views never talk to services directly: view models do,
// so real implementations (speech, backend, StoreKit) plug in without touching the UI.

/// Live transcription. The stream yields the full transcript recognized so far.
@MainActor
protocol SpeechService: AnyObject {
    func start() -> AsyncStream<String>
    func stop()
}

/// Turns a draft into an interpreted dream, reporting progress step by step.
protocol DreamAnalysisService: Sendable {
    func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, Error>
}

/// Persistence for dreams, newest first.
@MainActor
protocol DreamStore: AnyObject {
    var dreams: [Dream] { get }
    func dream(id: Dream.ID) -> Dream?
    /// Inserts a new dream or replaces the one with the same id.
    func save(_ dream: Dream)
    func deleteAll()
}

/// Subscriptions through the App Store. The store (RevenueCat, entitlement `premium`) is the only
/// source of truth for access; the backend mirrors it.
protocol PurchaseService: Sendable {
    /// The plans with this user's prices and trial eligibility.
    func products() async throws -> [PaywallProduct]
    func purchase(_ plan: Plan) async throws -> PurchaseOutcome
    /// Restores earlier purchases on this Apple ID.
    func restore() async throws -> EntitlementState
    /// Current access, then every change (renewal, expiry, refund) while the app runs.
    func entitlementUpdates() -> AsyncStream<EntitlementState>
    /// Ties purchases to the backend user id (RevenueCat app user id), so a subscription follows
    /// the account across reinstalls and devices.
    func logIn(userID: String) async
    /// Back to an anonymous purchaser after sign-out.
    func logOut() async
}

enum ReadAloudState: Equatable, Sendable { case idle, playing, paused }

/// Voice read-out of the interpretation.
@MainActor
protocol ReadAloudService: AnyObject {
    var state: ReadAloudState { get }
    /// 0...1 through the current text.
    var progress: Double { get }
    /// Starts reading `text`, or resumes if the same text is paused.
    func play(_ text: String)
    func pause()
    func stop()
}

/// Library content.
protocol SymbolCatalog: Sendable {
    var symbols: [LibrarySymbol] { get }
    func symbol(id: LibrarySymbol.ID) -> LibrarySymbol?
}

extension SymbolCatalog {
    func symbol(id: LibrarySymbol.ID) -> LibrarySymbol? { symbols.first { $0.id == id } }
}

/// Saves a dream image to the user's photo library.
protocol ImageSaving: Sendable {
    func saveImage(named assetName: String) async throws
}

/// Session-level preferences that survive relaunch.
struct UserPreferences: Codable, Hashable, Sendable {
    init() {}

    init(from decoder: any Decoder) throws {
        // Every field has a default, so preferences saved by an older build still load.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserPreferences()
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? defaults.userName
        goal = try container.decodeIfPresent(Goal.self, forKey: .goal)
        preferredLens = try container.decodeIfPresent(Lens.self, forKey: .preferredLens) ?? defaults.preferredLens
        subscription = try container.decodeIfPresent(SubscriptionStatus.self, forKey: .subscription) ?? defaults.subscription
        paywallBypassed = try container.decodeIfPresent(Bool.self, forKey: .paywallBypassed) ?? defaults.paywallBypassed
        reminders = try container.decodeIfPresent(ReminderSettings.self, forKey: .reminders) ?? defaults.reminders
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        paywallVariant = try container.decodeIfPresent(PaywallVariant.self, forKey: .paywallVariant)
        freeInterpretationsLeft = try container.decodeIfPresent(Int.self, forKey: .freeInterpretationsLeft) ?? 0
    }

    var onboardingCompleted = false
    /// First name from the account (Apple shares it once); empty = greet without a name.
    var userName = ""
    var goal: Goal?
    var preferredLens: Lens = .psychology
    var subscription: SubscriptionStatus = .none
    /// Phase 1 testing: lets the paywall close button reach Main.
    var paywallBypassed = false
    var reminders = ReminderSettings()
    /// Backend user id of the signed-in account (not secret; the tokens live in the Keychain).
    var userID: String?
    /// Last known from `GET /v1/subscription`, so the right screen shows before it answers again.
    var paywallVariant: PaywallVariant?
    var freeInterpretationsLeft = 0
}

@MainActor
protocol PreferencesStore: AnyObject {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}
