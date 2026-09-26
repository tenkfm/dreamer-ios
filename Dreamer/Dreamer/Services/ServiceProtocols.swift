import Foundation

// Service boundaries. Views never talk to services directly: view models do,
// so real implementations (speech, backend, StoreKit) plug in without touching the UI.

/// What live transcription reports while the user talks.
enum SpeechEvent: Sendable, Equatable {
    /// The whole transcript recognized so far (it can still change as recognition refines it).
    case transcript(String)
    /// Microphone level, 0...1, about 20 times a second (drives the waveform).
    case level(Float)
    /// The system took the microphone (a call, Siri, an alarm). The stream ends after this.
    case interrupted
    /// No live text for this recording (the language cannot be recognized on this iPhone, or
    /// recognition failed): the audio is still recorded and transcribed on the server at the end.
    case liveTextUnavailable
}

enum SpeechError: Error, Equatable {
    case notAuthorized
    case unavailable
    case audio(String)
}

/// Live transcription. `start` ends when `stop` is called or recognition fails.
@MainActor
protocol SpeechService: AnyObject {
    func start() -> AsyncThrowingStream<SpeechEvent, any Error>
    func stop()
    /// The audio is recorded as well, for the server fallback (IOS-04.5).
    var keepsAudio: Bool { get }
    /// Stops and hands over the audio recorded since the last take (nil when none or too short).
    /// The caller owns the file from then on and must delete it.
    func takeRecording() -> RecordedAudio?
    /// Stops and deletes any recorded audio.
    func discardRecording()
}

extension SpeechService {
    var keepsAudio: Bool { false }
    func takeRecording() -> RecordedAudio? { nil }
    func discardRecording() { stop() }
}

/// Turns a draft into an interpreted dream, reporting progress step by step.
protocol DreamAnalysisService: Sendable {
    func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, Error>
}

/// The user's dreams: the journal list (newest first) and the dreams opened in full. Reads are
/// synchronous from the device cache, so screens open at once; the async calls bring the server's
/// state into it.
@MainActor
protocol DreamStore: AnyObject {
    /// The journal as far as loaded, newest first.
    var summaries: [DreamSummary] { get }
    /// More pages wait on the server.
    var canLoadMore: Bool { get }
    /// The first page from the server replaces the cached list.
    func refresh() async throws(APIError)
    func loadMore() async throws(APIError)
    /// The dream in full, if it is on the device.
    func dream(id: Dream.ID) -> Dream?
    /// The dream in full from the server (fresh status and links), cached.
    func loadDream(id: Dream.ID) async throws(APIError) -> Dream
    /// Inserts a new dream or replaces the one with the same id (list entry included).
    func save(_ dream: Dream)
    /// Server search over the text and the interpretation (`snippet` = the matching fragment).
    /// Results are not cached: offline, the journal filters what the device has.
    func search(query: String?, emotion: Emotion?) async throws(APIError) -> [DreamSummary]
    /// Deletes on the server, then on the device.
    func delete(id: Dream.ID) async throws(APIError)
    /// Sign-out and account deletion: the device forgets every dream.
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
    /// The MMP's install id, for the purchase integration to attribute trials and purchases.
    func setAttribution(_ id: AttributionID)
}

extension PurchaseService {
    func setAttribution(_ id: AttributionID) {}
}

enum ReadAloudState: Equatable, Sendable {
    case idle
    /// Getting the voice from the backend (a lens that was not voiced yet).
    case loading
    case playing
    case paused
}

/// What to read aloud: the text for the on-device voice, and where the backend voice is.
struct ReadAloudItem: Equatable, Sendable {
    var text: String
    var lens: Lens
    /// Nil for text that is not a dream on the backend (previews).
    var dreamID: UUID?
    /// The voice the dream came with (the main lens is voiced with the interpretation).
    var audio: DreamAudio?
}

/// Voice read-out of the interpretation.
@MainActor
protocol ReadAloudService: AnyObject {
    var state: ReadAloudState { get }
    /// 0...1 through the current text.
    var progress: Double { get }
    /// Called when a read-out plays to its end.
    var onFinish: (@MainActor () -> Void)? { get set }
    /// Starts reading, or resumes if the same item is paused.
    func play(_ item: ReadAloudItem)
    /// Gets the voice ready before the tap, so Listen starts at once.
    func prepare(_ item: ReadAloudItem)
    func pause()
    func stop()
}

extension ReadAloudService {
    func prepare(_ item: ReadAloudItem) {}
}

/// Library content: reads from the device (the library works offline once opened), async calls
/// bring the server's.
@MainActor
protocol SymbolCatalog: AnyObject {
    /// Every symbol on the device, in the server's order.
    var symbols: [LibrarySymbol] { get }
    /// The symbols of a category, as last loaded.
    func symbols(in category: SymbolCategory) -> [LibrarySymbol]
    /// The symbol in full when it was opened before, else its list entry.
    func symbol(id: LibrarySymbol.ID) -> LibrarySymbol?
    func refresh(category: SymbolCategory) async throws(APIError)
    /// Server search over titles and meanings (all categories).
    func search(_ query: String) async throws(APIError) -> [LibrarySymbol]
    /// The symbol in full: every lens, the question, related symbols.
    func loadSymbol(id: LibrarySymbol.ID) async throws(APIError) -> LibrarySymbol
    /// The tile or hero image (cached on the device); nil in mock mode (the asset shows).
    func imageData(for symbol: LibrarySymbol) async -> Data?
}

/// Saves a dream image to the user's photo library.
protocol ImageSaving: Sendable {
    func saveImage(named assetName: String) async throws
    /// The downloaded dream image, as the backend made it.
    func saveImage(data: Data) async throws
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
        unsyncedProfile = try container.decodeIfPresent(ProfileUpdate.self, forKey: .unsyncedProfile)
        reminderPromptShown = try container.decodeIfPresent(Bool.self, forKey: .reminderPromptShown) ?? false
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
    /// Profile changes made on this device that the backend has not confirmed yet.
    var unsyncedProfile: ProfileUpdate?
    var reminderPromptShown = false
}

@MainActor
protocol PreferencesStore: AnyObject {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}
