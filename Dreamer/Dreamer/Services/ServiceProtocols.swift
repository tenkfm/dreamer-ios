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

protocol PurchaseService: Sendable {
    func purchase(_ plan: Plan) async throws
    /// Returns the restored plan, or nil when there is nothing to restore.
    func restore() async throws -> Plan?
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
    var onboardingCompleted = false
    var userName = "Anna"
    var goal: Goal?
    var preferredLens: Lens = .psychology
    var subscription: SubscriptionStatus = .none
    /// Phase 1 testing: lets "I already have an account" and the paywall close button reach Main.
    var paywallBypassed = false
    var reminders = ReminderSettings()
}

@MainActor
protocol PreferencesStore: AnyObject {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}
