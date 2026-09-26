import Foundation
import Testing
@testable import Dreamer

@MainActor
struct TrackingConsentTests {
    private func make(status: TrackingStatus = .notDetermined, answer: TrackingStatus = .authorized, afterFirstDream: Bool = false)
    -> (TrackingConsent, MockTrackingPermission, RecordingAttribution, RecordingAnalytics) {
        let permission = MockTrackingPermission(status: status, answer: answer)
        let attribution = RecordingAttribution()
        let analytics = RecordingAnalytics()
        let consent = TrackingConsent(permission: permission, analytics: analytics,
                                      measurement: MeasurementStack(attribution: attribution),
                                      askAfterFirstDream: afterFirstDream)
        return (consent, permission, attribution, analytics)
    }

    @Test func nothingStartsBeforeTheUserCouldSayNo() async {
        let (consent, _, attribution, _) = make()
        await consent.launched()
        #expect(attribution.starts.isEmpty)
    }

    @Test func anEarlierAnswerStartsMeasurementAtLaunch() async {
        let (consent, permission, attribution, _) = make(status: .denied)
        await consent.launched()
        consent.moment(.onboardingPaywall)
        #expect(attribution.starts == [false])
        #expect(!consent.isPrePromptPresented)
        #expect(permission.requests == 0)
    }

    @Test func thePaywallMomentAsksAndTheAnswerReachesEverySDK() async {
        let (consent, permission, attribution, analytics) = make(answer: .authorized)
        consent.moment(.firstInterpretation)
        #expect(!consent.isPrePromptPresented)

        consent.moment(.onboardingPaywall)
        #expect(consent.isPrePromptPresented)
        await consent.continueToSystemPrompt()

        #expect(permission.requests == 1)
        #expect(!consent.isPrePromptPresented)
        #expect(attribution.starts == [true])
        #expect(analytics.events == [.attResponse(status: .authorized)])
    }

    @Test func theFlagMovesTheQuestionAfterTheFirstDream() async {
        let (consent, _, attribution, analytics) = make(answer: .denied, afterFirstDream: true)
        consent.moment(.onboardingPaywall)
        #expect(!consent.isPrePromptPresented)
        consent.moment(.firstInterpretation)
        #expect(consent.isPrePromptPresented)
        await consent.continueToSystemPrompt()
        // Refused: measurement still starts, without the IDFA (SKAN/AEM only).
        #expect(attribution.starts == [false])
        #expect(analytics.events == [.attResponse(status: .denied)])
    }

    @Test func aRestrictedDeviceIsNeverAsked() async {
        let (consent, permission, attribution, _) = make(status: .restricted)
        await consent.launched()
        consent.moment(.onboardingPaywall)
        #expect(permission.requests == 0)
        #expect(attribution.starts == [false])
    }
}
