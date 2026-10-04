import Foundation
import os
import Testing
@testable import Dreamer

@MainActor
struct TrackingConsentTests {
    private func make(status: TrackingStatus = .notDetermined, answer: TrackingStatus = .authorized, afterFirstDream: Bool = false)
    -> (TrackingConsent, MockTrackingPermission, RecordingAttribution, RecordingPurchases) {
        let permission = MockTrackingPermission(status: status, answer: answer)
        let attribution = RecordingAttribution(id: .appsFlyer("af-uid"))
        let purchases = RecordingPurchases()
        let consent = TrackingConsent(permission: permission,
                                      measurement: MeasurementStack(attribution: attribution, purchases: purchases),
                                      askAfterFirstDream: afterFirstDream)
        return (consent, permission, attribution, purchases)
    }

    @Test func nothingStartsBeforeTheUserCouldSayNo() async {
        let (consent, _, attribution, purchases) = make()
        await consent.launched()
        #expect(attribution.starts.isEmpty)
        #expect(purchases.calls.isEmpty)
    }

    @Test func anEarlierAnswerStartsMeasurementAtLaunch() async {
        let (consent, permission, attribution, _) = make(status: .denied)
        await consent.launched()
        consent.moment(.firstHome)
        #expect(attribution.starts == [false])
        #expect(!consent.isPrePromptPresented)
        #expect(permission.requests == 0)
    }

    @Test func theFirstHomeAsksAndTheAnswerReachesEverySDK() async {
        let (consent, permission, attribution, purchases) = make(answer: .authorized)
        consent.moment(.firstInterpretation)
        #expect(!consent.isPrePromptPresented)

        consent.moment(.firstHome)
        #expect(consent.isPrePromptPresented)
        await consent.continueToSystemPrompt()

        #expect(permission.requests == 1)
        #expect(!consent.isPrePromptPresented)
        #expect(attribution.starts == [true])
        // RevenueCat gets the AppsFlyer id, and the device identifiers only now, after the answer.
        #expect(purchases.calls == ["attribution af-uid", "collect"])
    }

    @Test func theFlagMovesTheQuestionAfterTheFirstDream() async {
        let (consent, _, attribution, purchases) = make(answer: .denied, afterFirstDream: true)
        consent.moment(.firstHome)
        #expect(!consent.isPrePromptPresented)
        consent.moment(.firstInterpretation)
        #expect(consent.isPrePromptPresented)
        await consent.continueToSystemPrompt()
        // Refused: measurement still starts, without the IDFA (SKAN/AEM only).
        #expect(attribution.starts == [false])
        #expect(purchases.calls == ["attribution af-uid", "collect"])
    }

    @Test func aRestrictedDeviceIsNeverAsked() async {
        let (consent, permission, attribution, _) = make(status: .restricted)
        await consent.launched()
        consent.moment(.firstHome)
        #expect(permission.requests == 0)
        #expect(attribution.starts == [false])
    }
}

/// Records the attribution calls RevenueCat gets.
final class RecordingPurchases: PurchaseService, @unchecked Sendable {
    private let log = OSAllocatedUnfairLock<[String]>(initialState: [])
    var calls: [String] { log.withLock { $0 } }

    func products() async throws -> [PaywallProduct] { [] }
    func purchase(_ plan: Plan) async throws -> PurchaseOutcome { .cancelled }
    func restore() async throws -> EntitlementState { .none }
    func entitlementUpdates() -> AsyncStream<EntitlementState> { AsyncStream { $0.finish() } }
    func logIn(userID: String) async {}
    func logOut() async {}
    func setAttribution(_ id: AttributionID) {
        if case .appsFlyer(let value) = id { log.withLock { $0.append("attribution \(value)") } }
    }
    func collectDeviceIdentifiers() { log.withLock { $0.append("collect") } }
}

struct InstallCampaignTests {
    @Test func aPaidInstallKeepsItsCampaignAndCreative() throws {
        let campaign = try #require(InstallCampaign(conversionData: [
            "is_first_launch": true, "af_status": "Non-organic", "media_source": "tiktokglobal_int",
            "campaign": "gate1_dreams", "af_ad": "stairs_video_v2", "af_adset": "women_25_34", "install_time": "x"
        ]))
        #expect(campaign.userProperties == ["utm_source": "tiktokglobal_int", "utm_campaign": "gate1_dreams",
                                            "utm_content": "stairs_video_v2", "utm_term": "women_25_34"])
    }

    @Test func anOrganicInstallIsOrganic() throws {
        let campaign = try #require(InstallCampaign(conversionData: ["is_first_launch": "true", "af_status": "Organic"]))
        #expect(campaign == InstallCampaign(source: "organic", campaign: "", content: "", term: ""))
    }

    /// The SDK sends conversion data on later launches too: only the first one counts.
    @Test func laterLaunchesAreIgnored() {
        #expect(InstallCampaign(conversionData: ["is_first_launch": false, "af_status": "Organic"]) == nil)
        #expect(InstallCampaign(conversionData: [:]) == nil)
    }
}

struct AttributedAnalyticsTests {
    @Test func onlyThePaywallViewReachesTheMMP() {
        let base = RecordingAnalytics()
        let attribution = RecordingAttribution()
        let analytics = AttributedAnalytics(base: base, attribution: attribution)
        analytics.track(.paywallViewed(placement: .onboarding, variant: "oneFree"))
        analytics.track(.journalOpened)
        analytics.installAttributed(InstallCampaign(source: "organic", campaign: "", content: "", term: ""))
        #expect(base.events.count == 2)
        #expect(base.installCampaigns.count == 1)
        #expect(attribution.events == [.paywallViewed])
    }
}

@MainActor
struct RegistrationAttributionTests {
    private func session(isNew: Bool) -> AuthSession {
        AuthSession(accessToken: "a", accessExpiresAt: .distantFuture, refreshToken: "r", refreshExpiresAt: .distantFuture,
                    userID: "6b1f0c2e-0000-4000-8000-000000000001", isNewUser: isNew)
    }

    @Test func aNewAccountIsARegistrationAndAReturningOneIsNot() {
        let attribution = RecordingAttribution()
        OnboardingViewModel(appState: AppState(store: InMemoryPreferencesStore()), attribution: attribution)
            .signedIn(session(isNew: true))
        #expect(attribution.events == [.completeRegistration])

        let returning = RecordingAttribution()
        OnboardingViewModel(appState: AppState(store: InMemoryPreferencesStore()), attribution: returning)
            .signedIn(session(isNew: false))
        #expect(returning.events.isEmpty)
    }
}
