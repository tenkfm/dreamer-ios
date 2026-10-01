import AppTrackingTransparency
import Foundation
import Observation

/// The App Tracking Transparency answer.
enum TrackingStatus: String, Sendable {
    case notDetermined, authorized, denied
    /// Parental controls or MDM: the question cannot be asked.
    case restricted
}

@MainActor
protocol TrackingPermission: AnyObject {
    var status: TrackingStatus { get }
    /// The system alert (only while not determined).
    func request() async -> TrackingStatus
}

@MainActor
final class SystemTrackingPermission: TrackingPermission {
    var status: TrackingStatus { Self.map(ATTrackingManager.trackingAuthorizationStatus) }

    func request() async -> TrackingStatus {
        Self.map(await ATTrackingManager.requestTrackingAuthorization())
    }

    private static func map(_ status: ATTrackingManager.AuthorizationStatus) -> TrackingStatus {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

/// For previews, tests and mock mode.
@MainActor
final class MockTrackingPermission: TrackingPermission {
    var status: TrackingStatus
    let answer: TrackingStatus
    private(set) var requests = 0

    init(status: TrackingStatus = .notDetermined, answer: TrackingStatus = .denied) {
        self.status = status
        self.answer = answer
    }

    func request() async -> TrackingStatus {
        requests += 1
        status = answer
        return answer
    }
}

/// When to ask about tracking: our explanation first, then the system alert, at a moment chosen by
/// the `attAfterFirstDream` flag (A/B): on the first Home, or after the first interpretation. Install measurement starts with the answer; without consent the app works the
/// same and attribution relies on SKAN and AEM.
@MainActor
@Observable
final class TrackingConsent {
    enum Moment: Equatable {
        /// Home after onboarding, before the reminder offer (Tony: a modal over Home, not a step of
        /// the onboarding).
        case firstHome
        case firstInterpretation
    }

    private(set) var status: TrackingStatus
    /// Our explanation before the system alert.
    var isPrePromptPresented = false

    @ObservationIgnored private let permission: any TrackingPermission
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let measurement: MeasurementStack
    @ObservationIgnored private let moment: Moment
    @ObservationIgnored private var measurementStarted = false

    init(permission: any TrackingPermission, analytics: any Analytics, measurement: MeasurementStack, askAfterFirstDream: Bool) {
        self.permission = permission
        self.analytics = analytics
        self.measurement = measurement
        moment = askAfterFirstDream ? .firstInterpretation : .firstHome
        status = permission.status
    }

    /// Launch: an earlier answer (or a restriction) starts measurement at once; otherwise it waits
    /// for the question, so no SDK starts before the user could say no.
    func launched() async {
        guard status != .notDetermined else { return }
        await startMeasurement()
    }

    /// A moment of the flow has come; the question is asked if it is this variant's.
    func moment(_ moment: Moment) {
        guard moment == self.moment, status == .notDetermined, !isPrePromptPresented else { return }
        isPrePromptPresented = true
    }

    /// "Continue" on our explanation: the system alert, the answer to analytics and every SDK.
    func continueToSystemPrompt() async {
        isPrePromptPresented = false
        let answer = await permission.request()
        status = answer
        analytics.track(.attResponse(status: answer))
        await startMeasurement()
    }

    private func startMeasurement() async {
        guard !measurementStarted else { return }
        measurementStarted = true
        await measurement.start(trackingAllowed: status == .authorized)
    }
}
