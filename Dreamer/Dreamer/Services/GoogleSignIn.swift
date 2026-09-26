import AuthenticationServices
import CryptoKit
import Foundation

/// What Google sign-in hands the app, for the backend to verify (signature, audience = the iOS
/// client id, nonce) before it opens a session.
struct GoogleCredential: Sendable, Equatable {
    var idToken: String
    /// Google copies it into the id token as is; the backend checks that they match, so an id token
    /// lifted from another sign-in cannot be replayed.
    var rawNonce: String
}

enum GoogleSignInError: Error, Equatable, Sendable {
    /// The user closed the sheet or declined on Google's page: nothing to report.
    case cancelled
    case offline
    /// Google's answer was unusable: a state mismatch, no code, a failed exchange.
    case failed
}

/// Shows a URL in the system's web authentication sheet and returns the redirect it ended on.
/// The view passes SwiftUI's `webAuthenticationSession`, which knows the window to present from.
typealias WebAuthenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

/// Sign in with Google. There is no Google SDK: only the SDKs named in the tasks go in, and the
/// OAuth flow for native apps (RFC 8252) needs nothing beyond AuthenticationServices.
@MainActor
protocol GoogleSignInProvider: Sendable {
    func signIn(using browser: WebAuthenticator) async throws(GoogleSignInError) -> GoogleCredential
}

/// The iOS OAuth client of the Google Cloud project (`GOOGLE_IOS_CLIENT_ID`).
struct GoogleOAuthClient: Sendable, Equatable {
    let clientID: String

    /// Only an iOS client has the reversed-id redirect scheme that Google accepts without a
    /// client secret; a web client id here would fail on Google's page, so it is refused up front.
    init?(clientID: String) {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix), clientID.count > suffix.count, !clientID.contains("/") else { return nil }
        self.clientID = clientID
    }

    /// "123-abc.apps.googleusercontent.com" -> "com.googleusercontent.apps.123-abc".
    var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { callbackScheme + ":/oauth2redirect" }
}

/// One authorization attempt. The PKCE verifier, the state and the nonce are fresh each time:
/// the verifier stops an app that grabs the redirect from redeeming the code, the state ties the
/// redirect to this attempt.
struct GoogleAuthorizationRequest: Sendable {
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    let client: GoogleOAuthClient
    let codeVerifier: String
    let state: String
    let nonce: String

    init(client: GoogleOAuthClient,
         codeVerifier: String = AppleSignIn.randomNonce(length: 64),
         state: String = AppleSignIn.randomNonce(),
         nonce: String = AppleSignIn.randomNonce()) {
        self.client = client
        self.codeVerifier = codeVerifier
        self.state = state
        self.nonce = nonce
    }

    var codeChallenge: String {
        Data(SHA256.hash(data: Data(codeVerifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var url: URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            // Without it Google silently reuses the account signed in to Safari, and someone with
            // two accounts could never pick the other one.
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        return components.url!
    }

    /// The authorization code from Google's redirect.
    func authorizationCode(from callback: URL) throws(GoogleSignInError) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") == "access_denied" { throw .cancelled }
        guard value("state") == state, let code = value("code"), !code.isEmpty else { throw .failed }
        return code
    }

    /// Redeems the code with the verifier; an iOS client has no secret to send.
    func tokenRequest(code: String) -> URLRequest {
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        return request
    }

    static func idToken(from data: Data) throws(GoogleSignInError) -> String {
        struct TokenResponse: Decodable {
            let idToken: String?
            enum CodingKeys: String, CodingKey { case idToken = "id_token" }
        }
        guard let token = (try? JSONDecoder().decode(TokenResponse.self, from: data))?.idToken, !token.isEmpty else {
            throw .failed
        }
        return token
    }
}

/// Google's consent page in the system sheet, then the code exchange on the device. Only the id
/// token goes on to the backend; Google's access token is never kept.
struct WebGoogleSignIn: GoogleSignInProvider {
    let client: GoogleOAuthClient
    let session: URLSession

    init(client: GoogleOAuthClient, session: URLSession = WebGoogleSignIn.makeSession()) {
        self.client = client
        self.session = session
    }

    /// No cache: the token response holds the id token, which carries the user's email.
    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    func signIn(using browser: WebAuthenticator) async throws(GoogleSignInError) -> GoogleCredential {
        let request = GoogleAuthorizationRequest(client: client)
        let callback: URL
        do {
            callback = try await browser(request.url, client.callbackScheme)
        } catch {
            throw Self.isCancellation(error) ? .cancelled : .failed
        }
        let code = try request.authorizationCode(from: callback)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request.tokenRequest(code: code))
        } catch {
            throw Self.isOffline(error) ? .offline : .failed
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw .failed }
        return GoogleCredential(idToken: try GoogleAuthorizationRequest.idToken(from: data), rawNonce: request.nonce)
    }

    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    nonisolated static func isOffline(_ error: any Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                .timedOut, .dataNotAllowed].contains(code)
    }
}

/// Mock mode: every Google sign-in succeeds without a browser.
struct MockGoogleSignIn: GoogleSignInProvider {
    var delay: Duration = .milliseconds(600)
    var result: Result<GoogleCredential, GoogleSignInError> = .success(
        GoogleCredential(idToken: "mock-google-id-token", rawNonce: "mock-nonce"))

    func signIn(using browser: WebAuthenticator) async throws(GoogleSignInError) -> GoogleCredential {
        try? await Task.sleep(for: delay)
        return try result.get()
    }
}
