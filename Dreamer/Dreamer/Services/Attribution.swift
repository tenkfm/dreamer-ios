import Foundation
import os

/// The mobile measurement partner's id for this install. RevenueCat stores it as `$appsflyerId` or
/// `$adjustId`, so its server-side integration can send trial_start and purchase to the MMP.
enum AttributionID: Equatable, Sendable {
    case appsFlyer(String)
    case adjust(String)
}

/// What the app itself reports to the MMP for ad optimisation. Trials and purchases are not here:
/// RevenueCat's server integration sends them, and logging them too would count them twice.
enum AttributionEvent: Equatable, Sendable {
    /// The first sign-in of a new account.
    case completeRegistration
    case paywallViewed

    var name: String {
        switch self {
        case .completeRegistration: "af_complete_registration"
        case .paywallViewed: "paywall_viewed"
        }
    }
}

/// Install attribution (AppsFlyer, Tony's choice). The app starts it, names the user, reports two
/// events and hands the install id to RevenueCat; trial_start and purchase reach the MMP through
/// RevenueCat's server integration, not from app code.
protocol AttributionService: Sendable {
    /// The tracking answer is known (IOS-08.4): without consent only privacy-preserving
    /// attribution (SKAN, AEM) is used.
    func start(trackingAllowed: Bool) async
    /// Every return to the foreground: the MMP counts sessions from it.
    func appBecameActive()
    /// The backend user id (the MMP's customer user id); nil after sign-out.
    func setUserID(_ userID: String?)
    /// The MMP's id for this install, once the SDK has it.
    func attributionID() async -> AttributionID?
    func log(_ event: AttributionEvent)
}

extension AttributionService {
    func appBecameActive() {}
    func log(_ event: AttributionEvent) {}
}

/// Until the MMP is chosen: nothing is attributed (the rest of the app works the same).
struct NoopAttribution: AttributionService {
    func start(trackingAllowed: Bool) async {}
    func setUserID(_ userID: String?) {}
    func attributionID() async -> AttributionID? { nil }
}

/// Records calls, for tests.
final class RecordingAttribution: AttributionService, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(starts: [Bool], userIDs: [String?], events: [AttributionEvent])>(
        initialState: ([], [], []))
    let id: AttributionID?

    init(id: AttributionID? = nil) { self.id = id }

    /// `trackingAllowed` of every start.
    var starts: [Bool] { state.withLock { $0.starts } }
    var userIDs: [String?] { state.withLock { $0.userIDs } }
    var events: [AttributionEvent] { state.withLock { $0.events } }

    func start(trackingAllowed: Bool) async { state.withLock { $0.starts.append(trackingAllowed) } }
    func setUserID(_ userID: String?) { state.withLock { $0.userIDs.append(userID) } }
    func attributionID() async -> AttributionID? { id }
    func log(_ event: AttributionEvent) { state.withLock { $0.events.append(event) } }
}

/// An ad network's app-event SDK (Meta with Aggregated Event Measurement, TikTok Events). Trials
/// and purchases reach the networks through the MMP; the SDKs report installs and app opens and
/// honour the tracking answer. App ids, client token and the SKAN conversion schema are Tony's
/// (blocker IOS-08.3), so no network is registered until they exist.
protocol AdNetworkSDK: Sendable {
    /// For logs and tests ("meta", "tiktok").
    var name: String { get }
    /// Called once per launch after the tracking answer; `trackingAllowed` false = no IDFA, AEM/SKAN only.
    func start(trackingAllowed: Bool) async
}

/// Starts everything that measures installs, with the user's tracking answer.
struct MeasurementStack: Sendable {
    var attribution: any AttributionService = NoopAttribution()
    var adNetworks: [any AdNetworkSDK] = []
    /// RevenueCat: the MMP's install id, and the device identifiers once the answer is known (IDFA
    /// only with consent), so its MMP integration can attribute trials and purchases.
    var purchases: (any PurchaseService)?

    func start(trackingAllowed: Bool) async {
        await attribution.start(trackingAllowed: trackingAllowed)
        if let purchases {
            if let id = await attribution.attributionID() { purchases.setAttribution(id) }
            purchases.collectDeviceIdentifiers()
        }
        for network in adNetworks {
            await network.start(trackingAllowed: trackingAllowed)
        }
    }
}
