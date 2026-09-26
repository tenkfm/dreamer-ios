import Foundation
import os
import PostHog

/// A property value as the tracking plan types it (numbers and booleans stay numbers and booleans).
enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    var raw: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
        }
    }
}

/// `onboarding_step_viewed.step` values of the plan (the account step is not in it yet: blocker).
enum OnboardingStepName: String, Sendable {
    case welcome, record, understand, quizGoal, quizLens, paywall
}

/// `paywall_viewed.placement` values of the plan.
enum PaywallPlacement: String, Sendable {
    case onboarding, settings
    /// Shown because the free interpretation is used up (Record, Analysis).
    case limit
}

/// `read_aloud_fallback.reason` values of the plan.
enum ReadAloudFallbackReason: String, Sendable {
    case ttsUnavailable = "tts_unavailable"
    case audioFailed = "audio_failed"
    case timeout
    case network
}

/// `record_finished.input`: told aloud or typed.
enum RecordInput: String, Sendable {
    case voice, text
}

/// `quiz_answered`: the question decides the answer's type.
enum QuizAnswer: Equatable, Sendable {
    case goal(Goal)
    case lens(Lens)
}

/// Client-owned events of the tracking plan (dreamer-platform docs/tracking-plan.md, generated from
/// packages/shared/src/api/tracking.ts). Names, properties and their allowed values are fixed here
/// and nowhere else. No dream text, title, note, email, name or token is ever a property: only
/// enums, counts and ids of catalog content.
enum AnalyticsEvent: Equatable, Sendable {
    case onboardingStepViewed(step: OnboardingStepName)
    case quizAnswered(QuizAnswer)
    case paywallViewed(placement: PaywallPlacement, variant: String)
    case planSelected(plan: Plan)
    case purchaseStarted(plan: Plan)
    case signInStarted(method: SignInMethod)
    case recordStarted
    case recordFinished(seconds: Int, input: RecordInput)
    case detailsSubmitted(skipped: Bool, emotionsCount: Int)
    case interpretationViewed(lens: Lens)
    case lensPromoted(from: Lens, to: Lens)
    case readAloudPlayed(lens: Lens, fallback: Bool)
    case readAloudCompleted(lens: Lens, fallback: Bool, listenedPct: Int)
    case readAloudFallback(lens: Lens, reason: ReadAloudFallbackReason)
    case dreamShared(target: ShareTarget)
    case journalOpened
    case librarySymbolOpened(slug: String)
    case pushOpened(type: String)

    var name: String {
        switch self {
        case .onboardingStepViewed: "onboarding_step_viewed"
        case .quizAnswered: "quiz_answered"
        case .paywallViewed: "paywall_viewed"
        case .planSelected: "plan_selected"
        case .purchaseStarted: "purchase_started"
        case .signInStarted: "sign_in_started"
        case .recordStarted: "record_started"
        case .recordFinished: "record_finished"
        case .detailsSubmitted: "details_submitted"
        case .interpretationViewed: "interpretation_viewed"
        case .lensPromoted: "lens_promoted"
        case .readAloudPlayed: "read_aloud_played"
        case .readAloudCompleted: "read_aloud_completed"
        case .readAloudFallback: "read_aloud_fallback"
        case .dreamShared: "dream_shared"
        case .journalOpened: "journal_opened"
        case .librarySymbolOpened: "library_symbol_opened"
        case .pushOpened: "push_opened"
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case .onboardingStepViewed(let step): ["step": .string(step.rawValue)]
        case .quizAnswered(.goal(let goal)): ["question": .string("goal"), "answer": .string(goal.rawValue)]
        case .quizAnswered(.lens(let lens)): ["question": .string("lens"), "answer": .string(lens.rawValue)]
        case .paywallViewed(let placement, let variant):
            ["placement": .string(placement.rawValue), "variant": .string(String(variant.prefix(40)))]
        case .planSelected(let plan), .purchaseStarted(let plan): ["plan": .string(plan.rawValue)]
        case .signInStarted(let method): ["method": .string(method.rawValue)]
        case .recordStarted, .journalOpened: [:]
        case .recordFinished(let seconds, let input): ["seconds": .int(max(0, seconds)), "input": .string(input.rawValue)]
        case .detailsSubmitted(let skipped, let count): ["skipped": .bool(skipped), "emotionsCount": .int(min(max(count, 0), 5))]
        case .interpretationViewed(let lens): ["lens": .string(lens.rawValue)]
        case .lensPromoted(let from, let to): ["from": .string(from.rawValue), "to": .string(to.rawValue)]
        case .readAloudPlayed(let lens, let fallback): ["lens": .string(lens.rawValue), "fallback": .bool(fallback)]
        case .readAloudCompleted(let lens, let fallback, let pct):
            ["lens": .string(lens.rawValue), "fallback": .bool(fallback), "listenedPct": .int(min(max(pct, 0), 100))]
        case .readAloudFallback(let lens, let reason): ["lens": .string(lens.rawValue), "reason": .string(reason.rawValue)]
        case .dreamShared(let target): ["target": .string(target.rawValue)]
        case .librarySymbolOpened(let slug): ["slug": .string(String(slug.prefix(60)))]
        case .pushOpened(let type): ["type": .string(type)]
        }
    }
}

enum SignInMethod: String, Sendable {
    case apple, email
}

/// Where a dream card or image went (the tracking plan's `dream_shared.target`).
enum ShareTarget: String, Sendable {
    case shareSheet = "share_sheet"
    case photos
}

/// Product analytics (PostHog in the app, a recorder in tests).
protocol Analytics: Sendable {
    func track(_ event: AnalyticsEvent)
    /// A screen was shown (names from `AnalyticsScreen`).
    func screen(_ screen: AnalyticsScreen)
    /// Sent with every later event: the preferred lens and the paywall variant. Never personal data.
    func setContext(_ context: AnalyticsContext)
    /// The backend user id (the same distinct id the server uses). Never an email.
    func identify(userID: String)
    /// After sign-out and account deletion.
    func reset()
}

extension Analytics {
    func screen(_ screen: AnalyticsScreen) {}
    func setContext(_ context: AnalyticsContext) {}
}

/// Screen names for screen views.
enum AnalyticsScreen: String, Sendable {
    case onboarding = "Onboarding"
    case paywall = "Paywall"
    case home = "Home"
    case journal = "Journal"
    case library = "Library"
    case settings = "Settings"
    case interpretation = "Interpretation"
    case symbol = "Symbol"
    case record = "Record"
}

/// Super properties: who the user is in product terms, nothing personal.
struct AnalyticsContext: Equatable, Sendable {
    var preferredLens: Lens
    var paywallVariant: PaywallVariant

    var properties: [String: AnalyticsValue] {
        ["preferred_lens": .string(preferredLens.rawValue), "paywall_variant": .string(paywallVariant.rawValue)]
    }
}

struct NoopAnalytics: Analytics {
    private static let log = Logger(subsystem: "com.braincode.dreamer", category: "analytics")

    func track(_ event: AnalyticsEvent) {
        #if DEBUG
        Self.log.debug("event \(event.name, privacy: .public) \(event.properties.mapValues { "\($0.raw)" }.description, privacy: .public)")
        #endif
    }

    func identify(userID: String) {}
    func reset() {}
}

/// Records events for tests.
final class RecordingAnalytics: Analytics {
    private let storage = OSAllocatedUnfairLock<[AnalyticsEvent]>(initialState: [])
    private let identities = OSAllocatedUnfairLock<[String?]>(initialState: [])

    private let screens = OSAllocatedUnfairLock<[AnalyticsScreen]>(initialState: [])
    private let contexts = OSAllocatedUnfairLock<[AnalyticsContext]>(initialState: [])

    var events: [AnalyticsEvent] { storage.withLock { $0 } }
    var screenViews: [AnalyticsScreen] { screens.withLock { $0 } }
    var context: AnalyticsContext? { contexts.withLock { $0.last } }
    /// nil entries are resets.
    var identified: [String?] { identities.withLock { $0 } }

    func track(_ event: AnalyticsEvent) { storage.withLock { $0.append(event) } }
    func screen(_ screen: AnalyticsScreen) { screens.withLock { $0.append(screen) } }
    func setContext(_ context: AnalyticsContext) { contexts.withLock { $0.append(context) } }
    func identify(userID: String) { identities.withLock { $0.append(userID) } }
    func reset() { identities.withLock { $0.append(nil) } }
}

/// PostHog: the plan's events with typed properties, screen views, the context as super
/// properties, and the backend user id as the distinct id (the server sends under the same id).
struct PostHogAnalytics: Analytics {
    func track(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties.mapValues(\.raw))
    }

    func screen(_ screen: AnalyticsScreen) {
        PostHogSDK.shared.screen(screen.rawValue)
    }

    func setContext(_ context: AnalyticsContext) {
        PostHogSDK.shared.register(context.properties.mapValues(\.raw))
    }

    func identify(userID: String) {
        PostHogSDK.shared.identify(userID)
    }

    func reset() {
        PostHogSDK.shared.reset()
    }
}

enum AnalyticsFactory {
    /// PostHog when the build has its key; otherwise the debug log only.
    static func make(config: AppConfig) -> any Analytics {
        PostHogBootstrap.setUpIfNeeded(config: config) ? PostHogAnalytics() : NoopAnalytics()
    }
}
