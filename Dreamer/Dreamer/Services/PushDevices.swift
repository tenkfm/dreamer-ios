import Foundation

/// The backend's device registry for pushes (`/v1/devices`).
protocol DeviceRegistry: Sendable {
    func registerDevice(token: String, environment: PushEnvironment) async throws(APIError)
    func unregisterDevice(token: String) async throws(APIError)
}

extension APIClient: DeviceRegistry {}

/// Tells the backend where to send "your dream is ready": once per account and token, and never
/// after sign-out (the token is removed while the session still works).
@MainActor
final class PushDevices {
    private let registry: (any DeviceRegistry)?
    private let environment: PushEnvironment
    /// "user|token" last registered this session.
    private var registered: String?

    init(registry: (any DeviceRegistry)?, environment: PushEnvironment) {
        self.registry = registry
        self.environment = environment
    }

    func register(token: String?, userID: String?) async {
        guard let registry, let token, let userID, registered != "\(userID)|\(token)" else { return }
        do {
            try await registry.registerDevice(token: token, environment: environment)
            registered = "\(userID)|\(token)"
        } catch {
            // Tried again at the next launch or token change.
        }
    }

    /// Before sign-out: this phone stops getting the account's pushes.
    func unregister(token: String?) async {
        guard let registry, let token else { return }
        try? await registry.unregisterDevice(token: token)
        registered = nil
    }
}
