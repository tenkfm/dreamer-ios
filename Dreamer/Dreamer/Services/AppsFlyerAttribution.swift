import AppsFlyerLib
import Foundation

/// AppsFlyer: install attribution and the campaign of the install. The SDK waits up to a minute
/// for the tracking answer before it reports, then attributes with the IDFA only if allowed
/// (SKAN otherwise); a session is counted at every return to the foreground. The user is named
/// with our user id, the same one RevenueCat and PostHog use. On 6.x: 7.0 dropped that wait for
/// a listener the app must hold `start()` in, and our question comes minutes after the launch.
final class AppsFlyerAttribution: NSObject, AttributionService, AppsFlyerLibDelegate, @unchecked Sendable {
    private let analytics: any Analytics

    /// `userID`: a session restored at launch, so the install carries it from the first report.
    init(devKey: String, appleAppID: String, userID: String?, analytics: any Analytics) {
        self.analytics = analytics
        super.init()
        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = devKey
        sdk.appleAppID = appleAppID
        sdk.customerUserID = userID
        sdk.delegate = self
        sdk.waitForATTUserAuthorization(timeoutInterval: 60)
    }

    func start(trackingAllowed: Bool) async {
        // Through the synchronous method: in an async function `start()` resolves to the SDK's
        // completion-handler form, imported as async throws.
        appBecameActive()
    }

    func appBecameActive() {
        AppsFlyerLib.shared().start()
    }

    func setUserID(_ userID: String?) {
        AppsFlyerLib.shared().customerUserID = userID
    }

    func attributionID() async -> AttributionID? {
        .appsFlyer(AppsFlyerLib.shared().getAppsFlyerUID())
    }

    func log(_ event: AttributionEvent) {
        AppsFlyerLib.shared().logEvent(event.name, withValues: nil)
    }

    // MARK: AppsFlyerLibDelegate

    /// The first launch's campaign becomes the person's utm_* in PostHog, once. Nothing else of the
    /// conversion data leaves the device's SDK.
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        guard let campaign = InstallCampaign(conversionData: data) else { return }
        analytics.installAttributed(campaign)
    }

    func onConversionDataFail(_ error: any Error) {}
}

/// Where an install came from, as the Gate 1 dashboard splits the funnel: source, campaign,
/// creative and ad set.
struct InstallCampaign: Equatable, Sendable {
    var source: String
    var campaign: String
    var content: String
    var term: String

    /// Nil unless this is the first launch (the SDK sends conversion data on later launches too).
    init?(conversionData data: [AnyHashable: Any]) {
        let firstLaunch = (data["is_first_launch"] as? Bool) ?? ((data["is_first_launch"] as? String) == "true")
        guard firstLaunch else { return nil }
        let organic = (data["af_status"] as? String) == "Organic"
        source = organic ? "organic" : (data["media_source"] as? String) ?? "organic"
        campaign = (data["campaign"] as? String) ?? ""
        content = (data["af_ad"] as? String) ?? ""
        term = (data["af_adset"] as? String) ?? ""
    }

    init(source: String, campaign: String, content: String, term: String) {
        self.source = source
        self.campaign = campaign
        self.content = content
        self.term = term
    }

    /// Person properties, set once.
    var userProperties: [String: String] {
        ["utm_source": source, "utm_campaign": campaign, "utm_content": content, "utm_term": term]
    }
}
