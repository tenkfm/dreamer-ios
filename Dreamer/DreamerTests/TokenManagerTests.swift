import Foundation
import os
import Testing
@testable import Dreamer

struct TokenManagerTests {
    /// Counts refresh calls and hands out numbered sessions.
    final class RefreshCounter: Sendable {
        private let calls = OSAllocatedUnfairLock(initialState: 0)
        let result: @Sendable (Int) throws(APIError) -> AuthSession

        init(result: @escaping @Sendable (Int) throws(APIError) -> AuthSession = { n in TokenManagerTests.session("access-\(n)", validFor: 900) }) {
            self.result = result
        }

        var count: Int { calls.withLock { $0 } }

        func refresh(_ token: String) async throws(APIError) -> AuthSession {
            let n = calls.withLock { $0 += 1; return $0 }
            // Keep the refresh in flight long enough for every parallel caller to arrive.
            try? await Task.sleep(for: .milliseconds(80))
            return try result(n)
        }
    }

    static func session(_ access: String, validFor seconds: TimeInterval, refresh: String = "refresh") -> AuthSession {
        AuthSession(accessToken: access, accessExpiresAt: Date().addingTimeInterval(seconds),
                    refreshToken: refresh, refreshExpiresAt: Date().addingTimeInterval(86_400 * 60),
                    userID: "user-1", isNewUser: false)
    }

    @Test func tenParallelRequestsWithAnExpiredTokenRefreshOnce() async throws {
        let counter = RefreshCounter()
        let manager = TokenManager(store: InMemorySecureStore(), refresh: counter.refresh)
        await manager.start(Self.session("expired", validFor: -10))

        let (client, host) = StubURLProtocol.makeClient(tokens: manager) { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1"
                ? .json(200, #"{"days":[],"count":0}"#)
                : .json(401, #"{"error":{"code":"AUTH_INVALID_TOKEN","message":"expired"}}"#)
        }
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 { group.addTask { try await client.weekInsight().count } }
            for try await _ in group {}
        }

        #expect(counter.count == 1)
        #expect(StubURLProtocol.requests(for: host).count == 10)
    }

    @Test func tenParallelRejectionsRefreshOnce() async throws {
        let counter = RefreshCounter()
        let manager = TokenManager(store: InMemorySecureStore(), refresh: counter.refresh)
        // Looks valid locally but the server already revoked it.
        await manager.start(Self.session("stale", validFor: 900))

        let (client, _) = StubURLProtocol.makeClient(tokens: manager) { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1"
                ? .json(200, #"{"days":[],"count":0}"#)
                : .json(401, #"{"error":{"code":"AUTH_INVALID_TOKEN","message":"expired"}}"#)
        }
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 { group.addTask { try await client.weekInsight().count } }
            for try await _ in group {}
        }

        #expect(counter.count == 1)
    }

    @Test func rejectedRefreshSignsOut() async throws {
        let counter = RefreshCounter { _ throws(APIError) in
            throw APIError.server(.init(code: .authInvalidToken, message: "revoked", status: 401))
        }
        let store = InMemorySecureStore()
        let manager = TokenManager(store: store, refresh: counter.refresh)
        await manager.start(Self.session("expired", validFor: -10))
        let events = manager.signedOutEvents

        await #expect(throws: APIError.signedOut) { _ = try await manager.accessToken() }
        #expect(await manager.isSignedIn == false)
        #expect(try store.data(for: "authSession") == nil)

        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test func offlineRefreshKeepsTheSession() async {
        let counter = RefreshCounter { _ throws(APIError) in throw APIError.offline }
        let manager = TokenManager(store: InMemorySecureStore(), refresh: counter.refresh)
        await manager.start(Self.session("expired", validFor: -10))

        await #expect(throws: APIError.offline) { _ = try await manager.accessToken() }
        #expect(await manager.isSignedIn)
    }

    @Test func rotatedSessionIsPersistedImmediately() async throws {
        let store = InMemorySecureStore()
        let counter = RefreshCounter { n in TokenManagerTests.session("access-\(n)", validFor: 900, refresh: "rotated-\(n)") }
        let manager = TokenManager(store: store, refresh: counter.refresh)
        await manager.start(Self.session("expired", validFor: -10))

        #expect(try await manager.accessToken() == "access-1")

        let relaunched = TokenManager(store: store, refresh: counter.refresh)
        #expect(await relaunched.refreshToken == "rotated-1")
        #expect(try await relaunched.accessToken() == "access-1")
        #expect(counter.count == 1)
    }

    @Test func keychainRoundTrip() throws {
        let keychain = KeychainStore(service: "com.braincode.dreamer.tests.\(UUID().uuidString)")
        #expect(try keychain.data(for: "k") == nil)
        try keychain.set(Data("one".utf8), for: "k")
        try keychain.set(Data("two".utf8), for: "k")
        #expect(try keychain.data(for: "k") == Data("two".utf8))
        try keychain.set(nil, for: "k")
        #expect(try keychain.data(for: "k") == nil)
    }
}
