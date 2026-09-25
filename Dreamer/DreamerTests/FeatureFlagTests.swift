import Testing
@testable import Dreamer

struct FeatureFlagTests {
    @Test func defaultsKeepTheAppUsableOffline() {
        let flags = FeatureFlags.defaults
        #expect(flags.isEnabled(.ttsEnabled))
        #expect(flags.isEnabled(.serverSttFallback))
        #expect(flags.isEnabled(.imageGenerationEnabled))
        #expect(!flags.isEnabled(.attestationEnforced))
    }

    @Test func remoteValuesWinOverDefaults() {
        let flags = FeatureFlags([.imageGenerationEnabled: false, .attestationEnforced: true])
        #expect(!flags.isEnabled(.imageGenerationEnabled))
        #expect(flags.isEnabled(.attestationEnforced))
        #expect(flags.isEnabled(.ttsEnabled))
    }

    @Test func launchArgumentsOverrideFlags() {
        let flags = FeatureFlags([.ttsEnabled: true]).overridden(by: [
            "Dreamer", "-featureFlag", "ttsEnabled=false", "-featureFlag", "unknown=true", "-featureFlag", "serverSttFallback=maybe"
        ])
        #expect(!flags.isEnabled(.ttsEnabled))
        #expect(flags.isEnabled(.serverSttFallback))
    }

    @Test func serviceWithoutPostHogKeyUsesDefaults() {
        let service = PostHogFeatureFlagService(config: AppConfig(infoDictionary: [:]))
        #expect(service.flags == .defaults)
    }
}
