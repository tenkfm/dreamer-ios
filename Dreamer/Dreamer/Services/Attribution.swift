import Foundation
import os

/// The mobile measurement partner's id for this install. RevenueCat stores it as `$appsflyerId` or
/// `$adjustId`, so its server-side integration can send trial_start and purchase to the MMP.
enum AttributionID: Equatable, Sendable {
    case appsFlyer(String)
    case adjust(String)
}

/// Install attribution (AppsFlyer or Adjust: Tony's choice and dev key, blocker IOS-08.2). The app
/// only starts it, names the user and hands the install id to RevenueCat; install, trial_start and
/// purchase reach the MMP through its SDK and RevenueCat's server integration, not from app code.
protocol AttributionService: Sendable {
    /// Starts attribution. Called once per launch, after the tracking answer is known (IOS-08.4):
    /// without consent only privacy-preserving attribution (SKAN, AEM) is used.
    func start(trackingAllowed: Bool) async
    /// The backend user id (the MMP's customer user id); nil after sign-out.
    func setUserID(_ userID: String?)
    /// The MMP's id for this install, once the SDK has it.
    func attributionID() async -> AttributionID?
}

/// Until the MMP is chosen: nothing is attributed (the rest of the app works the same).
struct NoopAttribution: AttributionService {
    func start(trackingAllowed: Bool) async {}
    func setUserID(_ userID: String?) {}
    func attributionID() async -> AttributionID? { nil }
}

/// Records calls, for tests.
final class RecordingAttribution: AttributionService, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(starts: [Bool], userIDs: [String?])>(initialState: ([], []))
    let id: AttributionID?

    init(id: AttributionID? = nil) { self.id = id }

    /// `trackingAllowed` of every start.
    var starts: [Bool] { state.withLock { $0.starts } }
    var userIDs: [String?] { state.withLock { $0.userIDs } }

    func start(trackingAllowed: Bool) async { state.withLock { $0.starts.append(trackingAllowed) } }
    func setUserID(_ userID: String?) { state.withLock { $0.userIDs.append(userID) } }
    func attributionID() async -> AttributionID? { id }
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

    func start(trackingAllowed: Bool) async {
        await attribution.start(trackingAllowed: trackingAllowed)
        for network in adNetworks {
            await network.start(trackingAllowed: trackingAllowed)
        }
    }
}
