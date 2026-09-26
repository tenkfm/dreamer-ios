import Foundation
import LocalAuthentication
import Observation

/// Face ID / Touch ID with the device passcode as the fallback.
@MainActor
protocol DeviceAuthenticator: AnyObject {
    /// Biometrics or a passcode are set up on this iPhone.
    var isAvailable: Bool { get }
    func authenticate(reason: String) async -> Bool
}

@MainActor
final class SystemAuthenticator: DeviceAuthenticator {
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// For previews, tests and mock mode.
@MainActor
final class MockAuthenticator: DeviceAuthenticator {
    var isAvailable = true
    var answer = true
    private(set) var attempts = 0

    func authenticate(reason: String) async -> Bool {
        attempts += 1
        return answer
    }
}

/// "Lock journal with Face ID": the app opens covered, and covers itself again when it leaves the
/// foreground, until the owner authenticates. The dreams never show in the app switcher either.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    /// Covered while inactive (the app switcher snapshot), even when unlocked.
    private(set) var isShielded = false
    var alertMessage: String?

    @ObservationIgnored private let appState: AppState
    @ObservationIgnored private let authenticator: any DeviceAuthenticator
    @ObservationIgnored private var isAuthenticating = false

    static let reason = "Unlock your dream journal"

    init(appState: AppState, authenticator: any DeviceAuthenticator) {
        self.appState = appState
        self.authenticator = authenticator
        isLocked = appState.reminders.lockWithFaceID && appState.isSignedIn
    }

    private var isEnabled: Bool { appState.reminders.lockWithFaceID && appState.isSignedIn }

    /// Scene phase changes: background locks, inactive shields, active asks to unlock.
    func sceneChanged(active: Bool, background: Bool) async {
        if background, isEnabled { isLocked = true }
        isShielded = isEnabled && !active
        if active, isLocked { await unlock() }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        guard isEnabled else {
            isLocked = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: Self.reason) { isLocked = false }
    }

    /// The Settings switch: turning it on needs a successful check first (so nobody locks
    /// themselves out on an iPhone without Face ID or a passcode).
    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            appState.reminders.lockWithFaceID = false
            isLocked = false
            return
        }
        guard authenticator.isAvailable else {
            alertMessage = "Set up Face ID or a passcode in the iPhone Settings to lock your journal."
            return
        }
        if await authenticator.authenticate(reason: "Turn on the journal lock") {
            appState.reminders.lockWithFaceID = true
        }
    }
}
