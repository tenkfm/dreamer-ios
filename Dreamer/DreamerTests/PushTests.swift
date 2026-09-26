import Foundation
import os
import Testing
@testable import Dreamer

/// Records device calls in order, shared with other steps of a scenario.
final class RecordingRegistry: DeviceRegistry, @unchecked Sendable {
    let log: OSAllocatedUnfairLock<[String]>
    var failNext = false

    init(log: OSAllocatedUnfairLock<[String]> = OSAllocatedUnfairLock(initialState: [])) { self.log = log }

    var calls: [String] { log.withLock { $0 } }

    func registerDevice(token: String, environment: PushEnvironment) async throws(APIError) {
        if failNext { failNext = false; throw APIError.offline }
        log.withLock { $0.append("register \(token) \(environment.rawValue)") }
    }

    func unregisterDevice(token: String) async throws(APIError) {
        log.withLock { $0.append("unregister \(token)") }
    }
}

@MainActor
struct PushDeviceTests {
    @Test func aTokenIsRegisteredOncePerAccount() async {
        let registry = RecordingRegistry()
        let devices = PushDevices(registry: registry, environment: .production)
        await devices.register(token: "abc", userID: "user-1")
        await devices.register(token: "abc", userID: "user-1")
        await devices.register(token: "abc", userID: "user-2")
        #expect(registry.calls == ["register abc production", "register abc production"])
    }

    @Test func aFailureIsTriedAgain() async {
        let registry = RecordingRegistry()
        registry.failNext = true
        let devices = PushDevices(registry: registry, environment: .sandbox)
        await devices.register(token: "abc", userID: "user-1")
        await devices.register(token: "abc", userID: "user-1")
        #expect(registry.calls == ["register abc sandbox"])
    }

    @Test func nothingWithoutATokenOrAnAccount() async {
        let registry = RecordingRegistry()
        let devices = PushDevices(registry: registry, environment: .sandbox)
        await devices.register(token: nil, userID: "user-1")
        await devices.register(token: "abc", userID: nil)
        #expect(registry.calls.isEmpty)
    }

    @Test func signingOutRemovesTheTokenBeforeTheSessionEnds() async {
        let log = OSAllocatedUnfairLock<[String]>(initialState: [])
        let registry = RecordingRegistry(log: log)
        let devices = PushDevices(registry: registry, environment: .production)
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        let account = AccountController(auth: LoggingAuth(log: log), dreamStore: InMemoryDreamStore(seed: []), appState: appState,
                                        unlink: {}, unregisterPush: { await devices.unregister(token: "abc") })
        await account.signOut()
        #expect(log.withLock { $0 } == ["unregister abc", "logout"])
    }

    @Test func thePushTypesOpenTheDream() {
        let id = UUID()
        #expect(NotificationLink(userInfo: ["type": "interpretation_ready", "dreamId": id.uuidString]) == .dream(id))
        #expect(NotificationLink(userInfo: ["type": "image_ready", "dreamId": id.uuidString]) == .dream(id))
    }

    @Test func environmentFollowsTheEntitlement() {
        #expect(AppConfig(infoDictionary: ["DreamerAPSEnvironment": "production"]).pushEnvironment == .production)
        #expect(AppConfig(infoDictionary: ["DreamerAPSEnvironment": "development"]).pushEnvironment == .sandbox)
    }
}

/// Auth that writes "logout" into the shared log.
private struct LoggingAuth: AuthService {
    let log: OSAllocatedUnfairLock<[String]>
    let base = MockAuthService()
    func signInWithApple(_ credential: AppleCredential) async throws(APIError) -> AuthSession {
        try await base.signInWithApple(credential)
    }
    func requestEmailLink(email: String) async throws(APIError) { try await base.requestEmailLink(email: email) }
    func verifyEmailLink(token: String) async throws(APIError) -> AuthSession { try await base.verifyEmailLink(token: token) }
    func signOut() async { log.withLock { $0.append("logout") } }
    func deleteAccount() async throws(APIError) { try await base.deleteAccount() }
}
