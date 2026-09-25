import Foundation
import os
import PostHog

/// Starts the PostHog SDK once per process. Shared by feature flags and analytics.
enum PostHogBootstrap {
    /// Returns false when the configuration has no PostHog key, so callers fall back to local behavior.
    @discardableResult
    static func setUpIfNeeded(config: AppConfig) -> Bool {
        guard let projectToken = config.postHogAPIKey, let host = config.postHogHost else { return false }
        let isFirstCall = isSetUp.withLock { done in
            defer { done = true }
            return !done
        }
        guard isFirstCall else { return true }

        let postHog = PostHogConfig(projectToken: projectToken, host: host.absoluteString)
        // Events are sent explicitly by the analytics service (tracking plan), nothing automatic.
        postHog.captureApplicationLifecycleEvents = false
        postHog.captureScreenViews = false
        postHog.preloadFeatureFlags = true
        PostHogSDK.shared.setup(postHog)
        return true
    }

    private static let isSetUp = OSAllocatedUnfairLock(initialState: false)
}

/// Flags from PostHog. The SDK keeps the last fetched flags on disk: the session uses those
/// (so a change applies on the next launch), while a background reload refreshes the cache.
/// Without a key, or before the first successful fetch, every flag keeps its code default.
final class PostHogFeatureFlagService: FeatureFlagService {
    let flags: FeatureFlags

    init(config: AppConfig) {
        guard PostHogBootstrap.setUpIfNeeded(config: config) else {
            flags = .defaults
            return
        }
        var values: [FeatureFlag: Bool] = [:]
        for flag in FeatureFlag.allCases {
            if let value = PostHogSDK.shared.getFeatureFlag(flag.rawValue) as? Bool {
                values[flag] = value
            }
        }
        flags = FeatureFlags(values)
        PostHogSDK.shared.reloadFeatureFlags()
    }
}
