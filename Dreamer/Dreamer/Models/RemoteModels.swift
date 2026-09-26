import Foundation

// Domain models for data the backend owns. The API layer maps the generated contract types
// into these; nothing outside API/ sees the generated code.

// MARK: - Session and profile

struct AuthSession: Sendable, Equatable, Codable {
    var accessToken: String
    var accessExpiresAt: Date
    var refreshToken: String
    var refreshExpiresAt: Date
    var userID: String
    /// True on the first sign-in: the app sends the quiz answers next.
    var isNewUser: Bool
}

struct UserProfile: Sendable, Equatable {
    struct Reminder: Sendable, Equatable {
        var enabled: Bool
        /// "HH:MM", local time.
        var time: String
    }

    var id: String
    var email: String?
    var name: String?
    var goal: Goal?
    var preferredLens: Lens
    var reminder: Reminder
    /// IANA time zone the backend computes insights in.
    var timezone: String
    var nightMode: Bool
    var createdAt: Date
}

/// `PATCH /v1/me`: only the set fields change.
struct ProfileUpdate: Sendable, Hashable, Codable {
    var name: String?
    var goal: Goal?
    var preferredLens: Lens?
    var reminderEnabled: Bool?
    var reminderTime: String?
    var timezone: String?
    var nightMode: Bool?

    /// This update with `newer`'s fields on top (a later change of the same field wins).
    func merging(_ newer: ProfileUpdate) -> ProfileUpdate {
        ProfileUpdate(name: newer.name ?? name,
                      goal: newer.goal ?? goal,
                      preferredLens: newer.preferredLens ?? preferredLens,
                      reminderEnabled: newer.reminderEnabled ?? reminderEnabled,
                      reminderTime: newer.reminderTime ?? reminderTime,
                      timezone: newer.timezone ?? timezone,
                      nightMode: newer.nightMode ?? nightMode)
    }
}

// MARK: - Dreams

enum DreamStatus: String, Sendable, Codable {
    case analyzing, ready, failed
}

enum MediaStatus: String, Sendable, Codable {
    case pending, ready, failed
}

struct DreamImageInfo: Sendable, Equatable, Hashable, Codable {
    var status: MediaStatus
    var url: URL?
    /// 540 px wide.
    var previewURL: URL?
    /// 270 px wide.
    var thumbnailURL: URL?
    var width: Int?
    var height: Int?
    /// Grows with every regeneration; part of the image cache key.
    var version: Int

    init(status: MediaStatus, url: URL? = nil, previewURL: URL? = nil, thumbnailURL: URL? = nil,
         width: Int? = nil, height: Int? = nil, version: Int) {
        self.status = status
        self.url = url
        self.previewURL = previewURL
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.version = version
    }
}

struct WordTiming: Sendable, Equatable, Hashable, Codable {
    var word: String
    var start: TimeInterval
    var end: TimeInterval
}

struct DreamAudio: Sendable, Equatable, Hashable, Codable {
    var lens: Lens
    var status: MediaStatus
    var url: URL?
    var duration: TimeInterval?
    var wordTimings: [WordTiming]
}

/// `POST /v1/dreams`. `clientId` is generated once per dream and makes the call idempotent.
struct DreamSubmission: Sendable, Equatable, Codable {
    struct Details: Sendable, Equatable, Codable {
        var emotions: [Emotion]
        var recurrence: Recurrence
        var someoneSpecific: Bool
    }

    var clientId: String
    var text: String
    var details: Details?
    var recordedAt: Date?
    var recordingId: String?
}

/// A row of the journal (`GET /v1/dreams`).
struct DreamSummary: Sendable, Equatable, Identifiable, Codable {
    var id: UUID
    var createdAt: Date
    /// Monday of the dream's week (the backend groups the journal by it).
    var weekOf: Date
    var title: String?
    var status: DreamStatus
    var emotions: [Emotion]
    var thumbnailURL: URL?
    var symbols: [String]
    /// Matching fragment when the list was searched.
    var snippet: String?
    /// Mock mode: the thumbnail from the asset catalog (never from the backend).
    var assetName: String? = nil
}

extension DreamSummary {
    /// The journal entry of a dream the app has in full (a new dream, an opened one).
    init(_ dream: Dream, calendar: Calendar = .mondayFirst) {
        self.init(id: dream.id,
                  createdAt: dream.createdAt,
                  weekOf: calendar.dateInterval(of: .weekOfYear, for: dream.createdAt)?.start ?? dream.createdAt,
                  title: dream.title.isEmpty ? nil : dream.title,
                  status: dream.status,
                  emotions: dream.emotions,
                  thumbnailURL: dream.image?.thumbnailURL,
                  symbols: dream.symbols.map(\.keyword),
                  snippet: nil,
                  assetName: dream.thumbnailName ?? dream.imageName)
    }
}

extension Calendar {
    /// The backend's weeks start on Monday (`weekOf`).
    static var mondayFirst: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}

struct DreamPage: Sendable, Equatable {
    var items: [DreamSummary]
    /// Pass back as `cursor` until nil.
    var nextCursor: String?
}

/// `GET /v1/dreams/{id}/status`, the polling fallback of the event stream.
struct DreamProgress: Sendable, Equatable {
    var id: UUID
    var status: DreamStatus
    var analysisStep: Int
    var title: String?
    var errorCode: APIErrorCode?
}

/// `PATCH /v1/dreams/{id}`.
struct DreamPatch: Sendable, Equatable {
    var notes: String?
    var title: String?
}

struct ShareCard: Sendable, Equatable {
    var url: URL
    var width: Int
    var height: Int
}

/// `GET /v1/dreams/{id}/share-card` either has the card or is still rendering it.
enum ShareCardResult: Sendable, Equatable {
    case ready(ShareCard)
    case rendering(retryAfter: TimeInterval)
}

// MARK: - Recordings

struct RecordingUpload: Sendable, Equatable {
    var recordingId: String
    var uploadURL: URL
    var expiresAt: Date
}

// MARK: - Insights

struct WeekInsight: Sendable, Equatable, Codable {
    struct Day: Sendable, Equatable, Codable {
        var date: Date
        var letter: String
        var caught: Bool
        var isToday: Bool
    }

    var days: [Day]
    var count: Int
}

struct MorningInsight: Sendable, Equatable, Codable {
    var symbol: String
    var count: Int
    var text: String
}

struct MonthInsight: Sendable, Equatable, Codable {
    struct EmotionShare: Sendable, Equatable, Codable {
        var emotion: Emotion
        /// 0...1
        var share: Double
    }

    struct RecurringSymbol: Sendable, Equatable, Codable {
        var keyword: String
        var count: Int
    }

    /// "YYYY-MM"
    var month: String
    var monthName: String
    var dreamCount: Int
    var nightsSoFar: Int
    var topSymbol: String?
    var emotions: [EmotionShare]
    var recurringSymbols: [RecurringSymbol]
}

// MARK: - Library

struct LibraryPage: Sendable, Equatable {
    var items: [LibrarySymbol]
    var nextCursor: String?
}

// MARK: - Subscription

enum SubscriptionState: String, Sendable, Codable {
    case none, trialing, active, gracePeriod, billingIssue, cancelled, expired
}

/// Assigned by the backend at sign-up: `hard` shows the paywall before the first interpretation,
/// `oneFree` after it.
enum PaywallVariant: String, Sendable, Codable {
    case hard, oneFree
}

struct SubscriptionInfo: Sendable, Equatable {
    var state: SubscriptionState
    var isPremium: Bool
    var plan: Plan?
    var store: String?
    var expiresAt: Date?
    var willRenew: Bool
    var freeInterpretationsLeft: Int
    var paywallVariant: PaywallVariant
}

// MARK: - Devices and App Attest

enum PushEnvironment: String, Sendable {
    case sandbox, production
}

struct AttestChallenge: Sendable, Equatable {
    var challenge: String
    var expiresAt: Date
}
