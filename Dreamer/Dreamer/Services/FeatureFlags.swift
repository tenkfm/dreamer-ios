import Foundation

/// Remote switches. Keys match the flag keys in PostHog.
enum FeatureFlag: String, CaseIterable, Sendable {
    /// Read-out through the backend voice (ElevenLabs); off = on-device voice only.
    case ttsEnabled
    /// Send App Attest assertions and fail closed without them (the backend is in soft mode now).
    case attestationEnforced
    /// Fall back to server transcription when on-device recognition gives no text.
    case serverSttFallback
    /// Kill switch for dream image generation (regeneration and new images).
    case imageGenerationEnabled
    /// A/B of the tracking question: after the first interpretation instead of before the paywall.
    case attAfterFirstDream

    /// Used when the flag service is off or has never reached the server. Chosen so the app is
    /// fully usable without the network.
    var defaultValue: Bool {
        switch self {
        case .ttsEnabled: true
        case .attestationEnforced: false
        case .serverSttFallback: true
        case .imageGenerationEnabled: true
        case .attAfterFirstDream: false
        }
    }
}

/// Flag values for one app session. They never change while the app runs, so a flag flipped in
/// PostHog takes effect on the next launch instead of switching features under the user.
struct FeatureFlags: Sendable, Equatable {
    private let values: [FeatureFlag: Bool]

    init(_ values: [FeatureFlag: Bool] = [:]) {
        self.values = values
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        values[flag] ?? flag.defaultValue
    }

    static let defaults = FeatureFlags()

    /// Debug `-featureFlag name=true|false` launch arguments win over remote values.
    func overridden(by arguments: [String]) -> FeatureFlags {
        var merged = values
        for (index, argument) in arguments.enumerated() where argument == "-featureFlag" && index + 1 < arguments.count {
            let pair = arguments[index + 1].split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, let flag = FeatureFlag(rawValue: pair[0]), let value = Bool(pair[1]) else { continue }
            merged[flag] = value
        }
        return FeatureFlags(merged)
    }
}

/// Source of the session's flags.
protocol FeatureFlagService: Sendable {
    var flags: FeatureFlags { get }
}

/// Code defaults, for previews, tests, mock mode and builds without a PostHog key.
struct LocalFeatureFlagService: FeatureFlagService {
    let flags: FeatureFlags

    init(_ flags: FeatureFlags = .defaults) {
        self.flags = flags
    }
}
