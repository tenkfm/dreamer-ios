import Foundation

/// What Sign in with Apple hands the app, ready for `POST /v1/auth/apple`.
struct AppleCredential: Sendable, Equatable {
    var identityToken: String
    /// Lets the backend revoke the Apple grant when the account is deleted.
    var authorizationCode: String?
    /// The raw nonce; Apple received its SHA-256.
    var rawNonce: String
    /// Apple sends the name only on the very first sign-in.
    var givenName: String?
    var familyName: String?
}

/// Sign-in and session lifecycle. Successful sign-ins store the tokens before returning.
protocol AuthService: Sendable {
    func signInWithApple(_ credential: AppleCredential) async throws(APIError) -> AuthSession
    /// Sends the email with the sign-in link (always accepted, 5 an hour per address).
    func requestEmailLink(email: String) async throws(APIError)
    /// The token from the universal link `https://<api host>/auth/verify?token=...`.
    func verifyEmailLink(token: String) async throws(APIError) -> AuthSession
    /// Ends this device's session on the server (best effort) and forgets the tokens.
    func signOut() async
    /// Deletes the account and everything in it on the server, then forgets the tokens.
    func deleteAccount() async throws(APIError)
}

/// The backend. Tokens go to the TokenManager (Keychain) the moment they arrive.
struct APIAuthService: AuthService {
    let client: APIClient
    let tokens: TokenManager

    func signInWithApple(_ credential: AppleCredential) async throws(APIError) -> AuthSession {
        let session = try await client.signInWithApple(identityToken: credential.identityToken,
                                                       authorizationCode: credential.authorizationCode,
                                                       nonce: credential.rawNonce,
                                                       givenName: credential.givenName,
                                                       familyName: credential.familyName)
        await tokens.start(session)
        return session
    }

    func requestEmailLink(email: String) async throws(APIError) {
        try await client.requestEmailLink(email: email)
    }

    func verifyEmailLink(token: String) async throws(APIError) -> AuthSession {
        let session = try await client.verifyEmailLink(token: token)
        await tokens.start(session)
        return session
    }

    func signOut() async {
        if let refreshToken = await tokens.refreshToken {
            // Without the call the refresh token stays valid on the server for 60 days; a failure
            // (offline) still signs out locally - the token is forgotten either way.
            try? await client.logout(refreshToken: refreshToken)
        }
        await tokens.clear()
    }

    func deleteAccount() async throws(APIError) {
        try await client.deleteAccount()
        await tokens.clear()
    }
}

/// Local stand-in for previews, tests and `-mockServices`. Every sign-in succeeds; the email link
/// token "expired" answers AUTH_LINK_EXPIRED so that state can be tried.
actor MockAuthService: AuthService {
    /// Posted when a sign-in email "was sent" (UI tests open the link, `-uiTestOpenEmailLink`).
    static let linkSent = Notification.Name("MockAuthService.linkSent")

    private var nextUserIsNew: Bool
    private(set) var sentLinks: [String] = []
    private let delay: Duration

    init(nextUserIsNew: Bool = true, delay: Duration = .milliseconds(600)) {
        self.nextUserIsNew = nextUserIsNew
        self.delay = delay
    }

    func signInWithApple(_ credential: AppleCredential) async throws(APIError) -> AuthSession {
        try? await Task.sleep(for: delay)
        return makeSession()
    }

    func requestEmailLink(email: String) async throws(APIError) {
        try? await Task.sleep(for: delay)
        sentLinks.append(email)
        NotificationCenter.default.post(name: Self.linkSent, object: nil)
    }

    func verifyEmailLink(token: String) async throws(APIError) -> AuthSession {
        try? await Task.sleep(for: delay)
        if token == "expired" {
            throw APIError.server(.init(code: .authLinkExpired, message: "Link expired", status: 401))
        }
        return makeSession()
    }

    func signOut() async {}
    func deleteAccount() async throws(APIError) {}

    private func makeSession() -> AuthSession {
        defer { nextUserIsNew = false }
        return AuthSession(accessToken: "mock-access", accessExpiresAt: .now.addingTimeInterval(900),
                           refreshToken: "mock-refresh", refreshExpiresAt: .now.addingTimeInterval(86_400 * 60),
                           userID: "mock-user", isNewUser: nextUserIsNew)
    }
}
