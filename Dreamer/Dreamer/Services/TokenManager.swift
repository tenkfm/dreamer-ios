import Foundation

/// Owns the session tokens. The refresh token rotates on every use and reusing an old one makes
/// the backend revoke the whole session, so there is only ever one refresh in flight: every caller
/// that needs a fresh token waits for the same one.
actor TokenManager: AccessTokenProvider {
    typealias Refresh = @Sendable (_ refreshToken: String) async throws(APIError) -> AuthSession

    /// Refresh this long before the access token expires, so requests never race its expiry.
    static let refreshMargin: TimeInterval = 60

    private let store: any SecureStore
    private let refresh: Refresh
    private let now: @Sendable () -> Date
    private var session: AuthSession?
    private var refreshTask: Task<AuthSession, any Error>?
    private let (signedOutStream, signedOutContinuation) = AsyncStream<Void>.makeStream()

    private static let sessionKey = "authSession"

    init(store: any SecureStore, refresh: @escaping Refresh, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.refresh = refresh
        self.now = now
        session = (try? store.data(for: Self.sessionKey)).flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) }
    }

    /// Fires when the backend ends the session (refresh rejected): the app goes back to sign-in.
    nonisolated var signedOutEvents: AsyncStream<Void> { signedOutStream }

    var isSignedIn: Bool { session != nil }
    var userID: String? { session?.userID }
    var refreshToken: String? { session?.refreshToken }

    /// After sign-in: keep the new session.
    func start(_ newSession: AuthSession) {
        session = newSession
        persist()
    }

    /// After sign-out or account deletion.
    func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        persist()
    }

    // MARK: AccessTokenProvider

    func accessToken() async throws -> String? {
        guard let current = session else { return nil }
        if current.accessExpiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return current.accessToken
        }
        return try await refreshed().accessToken
    }

    func refreshAfterRejection(of token: String) async throws -> String {
        guard let current = session else { throw APIError.signedOut }
        // Another request already rotated the tokens after this one was sent.
        if current.accessToken != token { return current.accessToken }
        return try await refreshed().accessToken
    }

    // MARK: Refresh

    private func refreshed() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = session else { throw APIError.signedOut }

        let refresh = self.refresh
        let task = Task { () async throws -> AuthSession in
            try await refresh(current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let fresh = try await task.value
            session = fresh
            // The old refresh token is dead from this moment: store the new one before anything else.
            persist()
            return fresh
        } catch let error as APIError where error.endsSession {
            session = nil
            persist()
            signedOutContinuation.yield()
            throw APIError.signedOut
        }
        // Offline or a server hiccup: keep the session and let the caller report the error.
    }

    private func persist() {
        let data = session.flatMap { try? JSONEncoder().encode($0) }
        try? store.set(data, for: Self.sessionKey)
    }
}

private extension APIError {
    /// The refresh token itself was refused: the session cannot be recovered.
    var endsSession: Bool {
        switch code {
        case .authInvalidToken, .authRequired: true
        default: self == .signedOut
        }
    }
}
