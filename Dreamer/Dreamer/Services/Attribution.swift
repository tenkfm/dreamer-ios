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
    /// Starts attribution. Called once per launch, after the tracking answer is known (IOS-08.4).
    func start() async
    /// The backend user id (the MMP's customer user id); nil after sign-out.
    func setUserID(_ userID: String?)
    /// The MMP's id for this install, once the SDK has it.
    func attributionID() async -> AttributionID?
}

/// Until the MMP is chosen: nothing is attributed (the rest of the app works the same).
struct NoopAttribution: AttributionService {
    func start() async {}
    func setUserID(_ userID: String?) {}
    func attributionID() async -> AttributionID? { nil }
}

/// Records calls, for tests.
final class RecordingAttribution: AttributionService, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(starts: Int, userIDs: [String?])>(initialState: (0, []))
    let id: AttributionID?

    init(id: AttributionID? = nil) { self.id = id }

    var starts: Int { state.withLock { $0.starts } }
    var userIDs: [String?] { state.withLock { $0.userIDs } }

    func start() async { state.withLock { $0.starts += 1 } }
    func setUserID(_ userID: String?) { state.withLock { $0.userIDs.append(userID) } }
    func attributionID() async -> AttributionID? { id }
}
