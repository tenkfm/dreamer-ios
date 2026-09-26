import AuthenticationServices
import Foundation
import Testing
@testable import Dreamer

struct GoogleOAuthTests {
    private let client = GoogleOAuthClient(clientID: "123-abc.apps.googleusercontent.com")!

    @Test func onlyAnIOSClientIDIsAccepted() {
        #expect(GoogleOAuthClient(clientID: "") == nil)
        #expect(GoogleOAuthClient(clientID: ".apps.googleusercontent.com") == nil)
        #expect(GoogleOAuthClient(clientID: "123-abc") == nil)
        #expect(client.callbackScheme == "com.googleusercontent.apps.123-abc")
        #expect(client.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        #expect(AppConfig(infoDictionary: ["DreamerGoogleClientID": "123-abc.apps.googleusercontent.com"]).googleOAuthClient == client)
        // An unset build setting stays "$(GOOGLE_IOS_CLIENT_ID)": no button, not a broken one.
        #expect(AppConfig(infoDictionary: ["DreamerGoogleClientID": "$(GOOGLE_IOS_CLIENT_ID)"]).googleOAuthClient == nil)
    }

    @Test func authorizationURLCarriesPKCEStateAndNonce() throws {
        let request = GoogleAuthorizationRequest(client: client, codeVerifier: "dBjftJeZ4CVP-mJ92K9TUe0Z4NDBYZLGJK-QvjAQD8I",
                                                 state: "state-1", nonce: "nonce-1")
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.host == "accounts.google.com")
        #expect(query["client_id"] == client.clientID)
        #expect(query["redirect_uri"] == client.redirectURI)
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "openid email profile")
        #expect(query["code_challenge_method"] == "S256")
        // base64url(SHA-256(verifier)) without padding.
        #expect(query["code_challenge"] == "ZI0urbZnWWd4oIB8dsr19sBebA-PvptdgBQbVgurLgs")
        #expect(query["state"] == "state-1")
        #expect(query["nonce"] == "nonce-1")
        // The verifier itself never goes to the browser.
        #expect(!request.url.absoluteString.contains(request.codeVerifier))
    }

    @Test func everyAttemptIsFresh() {
        let first = GoogleAuthorizationRequest(client: client)
        let second = GoogleAuthorizationRequest(client: client)
        #expect(first.codeVerifier.count == 64)
        #expect(first.codeVerifier != second.codeVerifier)
        #expect(first.state != second.state)
        #expect(first.nonce != second.nonce)
    }

    @Test func callbackIsCheckedAgainstTheState() throws {
        let request = GoogleAuthorizationRequest(client: client, state: "state-1")
        let base = client.redirectURI
        #expect(try request.authorizationCode(from: URL(string: base + "?state=state-1&code=4/abc")!) == "4/abc")
        #expect(throws: GoogleSignInError.failed) {
            try request.authorizationCode(from: URL(string: base + "?state=other&code=4/abc")!)
        }
        #expect(throws: GoogleSignInError.failed) {
            try request.authorizationCode(from: URL(string: base + "?state=state-1")!)
        }
        #expect(throws: GoogleSignInError.cancelled) {
            try request.authorizationCode(from: URL(string: base + "?error=access_denied&state=state-1")!)
        }
    }

    @Test func tokenRequestRedeemsTheCodeWithTheVerifier() throws {
        let request = GoogleAuthorizationRequest(client: client, codeVerifier: "verifier-1")
        let token = request.tokenRequest(code: "4/abc")
        #expect(token.url == GoogleAuthorizationRequest.tokenEndpoint)
        #expect(token.httpMethod == "POST")
        let body = try #require(token.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let form = Dictionary(uniqueKeysWithValues: (URLComponents(string: "?" + body)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(form == ["code": "4/abc", "client_id": client.clientID, "code_verifier": "verifier-1",
                         "redirect_uri": client.redirectURI, "grant_type": "authorization_code"])
        #expect(!body.contains("secret"))
    }

    @Test func idTokenComesFromTheTokenResponse() throws {
        #expect(try GoogleAuthorizationRequest.idToken(from: Data(#"{"access_token":"a","id_token":"eyJ.x.y"}"#.utf8)) == "eyJ.x.y")
        #expect(throws: GoogleSignInError.failed) {
            try GoogleAuthorizationRequest.idToken(from: Data(#"{"access_token":"a"}"#.utf8))
        }
    }

    @Test func errorsAreSortedForTheScreen() {
        #expect(WebGoogleSignIn.isCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
        #expect(!WebGoogleSignIn.isCancellation(URLError(.badURL)))
        #expect(WebGoogleSignIn.isOffline(URLError(.notConnectedToInternet)))
        #expect(!WebGoogleSignIn.isOffline(URLError(.badServerResponse)))
    }
}

@MainActor
struct WebGoogleSignInTests {
    @Test func browserThenExchangeGivesTheIDTokenAndTheNonce() async throws {
        let client = GoogleOAuthClient(clientID: "123-abc.apps.googleusercontent.com")!
        let session = StubURLProtocol.makeSession(host: "oauth2.googleapis.com") { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return body.contains("code=bad") ? .json(400, #"{"error":"invalid_grant"}"#)
                                             : .json(200, #"{"access_token":"a","id_token":"eyJ.google.token"}"#)
        }
        let google = WebGoogleSignIn(client: client, session: session)
        var sentNonce: String?
        var sentScheme: String?

        let credential = try await google.signIn { url, scheme in
            sentScheme = scheme
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = query.first { $0.name == "state" }?.value ?? ""
            sentNonce = query.first { $0.name == "nonce" }?.value
            return URL(string: "\(scheme):/oauth2redirect?state=\(state)&code=good")!
        }

        #expect(credential.idToken == "eyJ.google.token")
        #expect(credential.rawNonce == sentNonce)
        #expect(sentScheme == client.callbackScheme)

        await #expect(throws: GoogleSignInError.failed) {
            try await google.signIn { url, scheme in
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
                return URL(string: "\(scheme):/oauth2redirect?state=\(state)&code=bad")!
            }
        }
        await #expect(throws: GoogleSignInError.cancelled) {
            try await google.signIn { _, _ in throw ASWebAuthenticationSessionError(.canceledLogin) }
        }
    }
}

@MainActor
struct GoogleSignInViewModelTests {
    private let browser: WebAuthenticator = { url, _ in url }

    @Test func googleSignInOpensTheSessionWithoutTrackingAnUnplannedValue() async {
        let analytics = RecordingAnalytics()
        var received: AuthSession?
        let viewModel = SignInViewModel(mode: .signUp, auth: MockAuthService(delay: .zero),
                                        google: MockGoogleSignIn(delay: .zero), analytics: analytics) { received = $0 }
        #expect(viewModel.isGoogleAvailable)

        await viewModel.signInWithGoogle(using: browser)

        #expect(received?.userID == "mock-user")
        #expect(!viewModel.isWorking)
        #expect(viewModel.workingMethod == nil)
        #expect(analytics.events.isEmpty)
    }

    @Test func withoutAClientTheButtonIsHidden() {
        let viewModel = SignInViewModel(mode: .signIn, auth: MockAuthService(delay: .zero)) { _ in }
        #expect(!viewModel.isGoogleAvailable)
    }

    @Test func cancelShowsNothingAndFailuresSayWhatHappened() async {
        func run(_ error: GoogleSignInError) async -> SignInViewModel {
            let viewModel = SignInViewModel(mode: .signUp, auth: MockAuthService(delay: .zero),
                                            google: MockGoogleSignIn(delay: .zero, result: .failure(error))) { _ in
                Issue.record("signed in after \(error)")
            }
            await viewModel.signInWithGoogle(using: browser)
            #expect(!viewModel.isWorking)
            return viewModel
        }
        #expect(await run(.cancelled).error == nil)
        #expect(await run(.offline).error?.kind == .offline)
        #expect(await run(.failed).error?.title == "Sign in with Google didn’t work")
    }

    @Test func liveBackendHasNoGoogleEndpointYet() async throws {
        let (client, host) = StubURLProtocol.makeClient { _ in .empty(500) }
        let tokens = TokenManager(store: InMemorySecureStore()) { _ throws(APIError) in throw .signedOut }
        let auth = APIAuthService(client: client, tokens: tokens)
        await #expect(throws: APIError.notConfigured) {
            try await auth.signInWithGoogle(GoogleCredential(idToken: "t", rawNonce: "n"))
        }
        #expect(StubURLProtocol.requests(for: host).isEmpty)
        #expect(await !tokens.isSignedIn)
    }
}
