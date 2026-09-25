import Foundation
import os

/// Client-owned events of the tracking plan (dreamer-platform docs/tracking-plan.md, generated from
/// packages/shared). Names and properties are fixed here and nowhere else. No dream text, title,
/// note, email, name or token is ever a property: only enums, counts and ids of catalog content.
enum AnalyticsEvent: Equatable, Sendable {
    case onboardingStepViewed(step: String)
    case quizAnswered(question: String, answer: String)
    case paywallViewed(placement: String, variant: String)
    case planSelected(plan: String)
    case purchaseStarted(plan: String)
    case signInStarted(method: SignInMethod)
    case recordStarted
    /// `input`: "voice" or "text".
    case recordFinished(seconds: Int, input: String)
    case detailsSubmitted(skipped: Bool, emotionsCount: Int)
    case interpretationViewed(lens: Lens)
    case lensPromoted(from: Lens, to: Lens)
    case readAloudPlayed(lens: Lens, fallback: Bool)
    case readAloudCompleted(lens: Lens, fallback: Bool, listenedPct: Int)
    case readAloudFallback(lens: Lens, reason: String)
    case dreamShared(target: String)
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

    var properties: [String: String] {
        switch self {
        case .onboardingStepViewed(let step): ["step": step]
        case .quizAnswered(let question, let answer): ["question": question, "answer": answer]
        case .paywallViewed(let placement, let variant): ["placement": placement, "variant": variant]
        case .planSelected(let plan), .purchaseStarted(let plan): ["plan": plan]
        case .signInStarted(let method): ["method": method.rawValue]
        case .recordStarted, .journalOpened: [:]
        case .recordFinished(let seconds, let input): ["seconds": String(seconds), "input": input]
        case .detailsSubmitted(let skipped, let count): ["skipped": String(skipped), "emotionsCount": String(count)]
        case .interpretationViewed(let lens): ["lens": lens.rawValue]
        case .lensPromoted(let from, let to): ["from": from.rawValue, "to": to.rawValue]
        case .readAloudPlayed(let lens, let fallback): ["lens": lens.rawValue, "fallback": String(fallback)]
        case .readAloudCompleted(let lens, let fallback, let pct):
            ["lens": lens.rawValue, "fallback": String(fallback), "listenedPct": String(pct)]
        case .readAloudFallback(let lens, let reason): ["lens": lens.rawValue, "reason": reason]
        case .dreamShared(let target): ["target": target]
        case .librarySymbolOpened(let slug): ["slug": slug]
        case .pushOpened(let type): ["type": type]
        }
    }
}

enum SignInMethod: String, Sendable {
    case apple, email
}

/// Product analytics. The PostHog implementation arrives with IOS-08.1; until then events go
/// nowhere in release builds and to the debug log in debug builds.
protocol Analytics: Sendable {
    func track(_ event: AnalyticsEvent)
    /// The backend user id (the same distinct id the server uses). Never an email.
    func identify(userID: String)
    /// After sign-out and account deletion.
    func reset()
}

struct NoopAnalytics: Analytics {
    private static let log = Logger(subsystem: "com.braincode.dreamer", category: "analytics")

    func track(_ event: AnalyticsEvent) {
        #if DEBUG
        Self.log.debug("event \(event.name, privacy: .public) \(event.properties.description, privacy: .public)")
        #endif
    }

    func identify(userID: String) {}
    func reset() {}
}

/// Records events for tests.
final class RecordingAnalytics: Analytics {
    private let storage = OSAllocatedUnfairLock<[AnalyticsEvent]>(initialState: [])
    private let identities = OSAllocatedUnfairLock<[String?]>(initialState: [])

    var events: [AnalyticsEvent] { storage.withLock { $0 } }
    /// nil entries are resets.
    var identified: [String?] { identities.withLock { $0 } }

    func track(_ event: AnalyticsEvent) { storage.withLock { $0.append(event) } }
    func identify(userID: String) { identities.withLock { $0.append(userID) } }
    func reset() { identities.withLock { $0.append(nil) } }
}
