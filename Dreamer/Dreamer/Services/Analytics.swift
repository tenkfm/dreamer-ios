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
    /// The App Tracking Transparency answer (IOS-08.4; not in tracking.ts yet, blocker).

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
    case apple, google, email
}

/// Where a dream card or image went (the tracking plan's `dream_shared.target`).
enum ShareTarget: String, Sendable {
    case shareSheet = "share_sheet"
    case photos
}

/// Product analytics (PostHog in the app, a recorder in tests).
protocol Analytics: Sendable {
    func track(_ event: AnalyticsEvent)
    /// Sent with every later event: the preferred lens and the paywall variant. Never personal data.
    func setContext(_ context: AnalyticsContext)
    /// The backend user id (the same distinct id the server uses). Never an email.
    func identify(userID: String)
    /// After sign-out and account deletion.
    func reset()
    /// The install's campaign from the MMP, on the first launch: `app_installed`, with the campaign
    /// as person properties set once (utm_*), so the funnel splits by campaign and creative.
    func installAttributed(_ campaign: InstallCampaign)
}

extension Analytics {
    func setContext(_ context: AnalyticsContext) {}
    func installAttributed(_ campaign: InstallCampaign) {}
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
    private static let log = Logger(subsystem: "com.braincode.dreamer.io", category: "analytics")

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

    private let installs = OSAllocatedUnfairLock<[InstallCampaign]>(initialState: [])
    private let contexts = OSAllocatedUnfairLock<[AnalyticsContext]>(initialState: [])

    var events: [AnalyticsEvent] { storage.withLock { $0 } }
    var installCampaigns: [InstallCampaign] { installs.withLock { $0 } }
    var context: AnalyticsContext? { contexts.withLock { $0.last } }
    /// nil entries are resets.
    var identified: [String?] { identities.withLock { $0 } }

    func track(_ event: AnalyticsEvent) { storage.withLock { $0.append(event) } }
    func installAttributed(_ campaign: InstallCampaign) { installs.withLock { $0.append(campaign) } }
    func setContext(_ context: AnalyticsContext) { contexts.withLock { $0.append(context) } }
    func identify(userID: String) { identities.withLock { $0.append(userID) } }
    func reset() { identities.withLock { $0.append(nil) } }
}

/// PostHog: exactly the plan's events with typed properties (no screen views: the plan has none),
/// the context as super properties, and the backend user id as the distinct id (the server sends
/// under the same id).
struct PostHogAnalytics: Analytics {
    func track(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties.mapValues(\.raw))
    }

    func installAttributed(_ campaign: InstallCampaign) {
        PostHogSDK.shared.capture("app_installed", userPropertiesSetOnce: campaign.userProperties)
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

/// Sends the plan's events on, and the paywall views to the MMP too, where they optimise the ads:
/// one place for every paywall.
struct AttributedAnalytics: Analytics {
    let base: any Analytics
    let attribution: any AttributionService

    func track(_ event: AnalyticsEvent) {
        base.track(event)
        if case .paywallViewed = event { attribution.log(.paywallViewed) }
    }

    func setContext(_ context: AnalyticsContext) { base.setContext(context) }
    func identify(userID: String) { base.identify(userID: userID) }
    func reset() { base.reset() }
    func installAttributed(_ campaign: InstallCampaign) { base.installAttributed(campaign) }
}

enum AnalyticsFactory {
    /// PostHog when the build has its key; otherwise the debug log only.
    static func make(config: AppConfig) -> any Analytics {
        PostHogBootstrap.setUpIfNeeded(config: config) ? PostHogAnalytics() : NoopAnalytics()
    }
}
