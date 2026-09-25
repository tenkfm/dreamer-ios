import Foundation
import Testing
@testable import Dreamer

struct AppConfigTests {
    @Test func readsValuesFromInfoDictionary() {
        let config = AppConfig(infoDictionary: [
            "DreamerEnvironment": "staging",
            "DreamerAPIBaseURL": "https://api-staging-0ea4.up.railway.app",
            "DreamerPostHogHost": "https://eu.i.posthog.com",
            "DreamerRevenueCatAPIKey": "appl_test"
        ])

        #expect(config.environment == .staging)
        #expect(config.apiBaseURL?.host() == "api-staging-0ea4.up.railway.app")
        #expect(config.postHogHost?.absoluteString == "https://eu.i.posthog.com")
        #expect(config.revenueCatAPIKey == "appl_test")
    }

    @Test func emptyAndUnexpandedValuesAreMissing() {
        let config = AppConfig(infoDictionary: [
            "DreamerEnvironment": "production",
            "DreamerAPIBaseURL": "",
            "DreamerSentryDSN": "$(SENTRY_DSN)",
            "DreamerPostHogAPIKey": "   "
        ])

        #expect(config.environment == .production)
        #expect(config.apiBaseURL == nil)
        #expect(config.sentryDSN == nil)
        #expect(config.postHogAPIKey == nil)
    }

    @Test func unknownEnvironmentFallsBackToDebug() {
        #expect(AppConfig(infoDictionary: [:]).environment == .debug)
    }
}
