import Foundation
import GoogleSignIn
import Testing
@testable import Dreamer

struct GoogleClientIDTests {
    @Test func onlyAnIOSClientIDTurnsTheButtonOn() {
        #expect(GoogleClientID.validated(nil) == nil)
        #expect(GoogleClientID.validated("") == nil)
        #expect(GoogleClientID.validated(".apps.googleusercontent.com") == nil)
        #expect(GoogleClientID.validated("123-abc") == nil)
        #expect(GoogleClientID.validated("123-abc.apps.googleusercontent.com") == "123-abc.apps.googleusercontent.com")
        #expect(AppConfig(infoDictionary: ["GIDClientID": "123-abc.apps.googleusercontent.com"]).googleClientID
                == "123-abc.apps.googleusercontent.com")
        // An unset build setting stays "$(GOOGLE_IOS_CLIENT_ID)": no button rather than an SDK crash.
        #expect(AppConfig(infoDictionary: ["GIDClientID": "$(GOOGLE_IOS_CLIENT_ID)"]).googleClientID == nil)
    }

    @Test func theBuildCarriesTheClientAndItsURLScheme() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let clientID = try #require(AppConfig(infoDictionary: info).googleClientID)
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        // Google returns through the reversed client id; without the scheme the sheet never closes.
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        #expect(schemes.contains(reversed))
    }

    @Test func sdkErrorsAreSortedForTheScreen() {
        let cancelled = NSError(domain: kGIDSignInErrorDomain, code: GIDSignInError.canceled.rawValue)
        #expect(GoogleSDKSignIn.error(for: cancelled) == .cancelled)
        #expect(GoogleSDKSignIn.error(for: URLError(.notConnectedToInternet)) == .offline)
        #expect(GoogleSDKSignIn.error(for: NSError(domain: kGIDSignInErrorDomain, code: GIDSignInError.unknown.rawValue)) == .failed)
    }
}

@MainActor
struct GoogleSignInViewModelTests {
    @Test func googleSignInOpensTheSessionAndIsTracked() async {
        let analytics = RecordingAnalytics()
        var received: AuthSession?
        let viewModel = SignInViewModel(mode: .signUp, auth: MockAuthService(delay: .zero),
                                        google: MockGoogleSignIn(delay: .zero), analytics: analytics) { received = $0 }
        #expect(viewModel.isGoogleAvailable)

        await viewModel.signInWithGoogle()

        #expect(received?.userID == "mock-user")
        #expect(!viewModel.isWorking)
        #expect(viewModel.workingMethod == nil)
        #expect(analytics.events == [.signInStarted(method: .google)])
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
            await viewModel.signInWithGoogle()
            #expect(!viewModel.isWorking)
            return viewModel
        }
        #expect(await run(.cancelled).error == nil)
        #expect(await run(.offline).error?.kind == .offline)
        #expect(await run(.failed).error?.title == "Sign in with Google didn’t work")
    }

    @Test func theIDTokenGoesToTheBackendAndTheSessionIsKept() async throws {
        let recorder = BodyRecorder()
        let (client, host) = StubURLProtocol.makeClient(middlewares: [recorder]) { request in
            #expect(request.url?.path() == "/v1/auth/google")
            return .json(200, """
            {"accessToken":"acc","accessExpiresAt":"2026-10-01T07:27:00.000Z","refreshToken":"ref",
             "refreshExpiresAt":"2026-11-30T07:12:00.000Z","user":{"id":"6f1d2c3b-4a5e-4f60-8a7b-9c0d1e2f3a4b","isNew":true}}
            """)
        }
        let store = InMemorySecureStore()
        let tokens = TokenManager(store: store) { _ throws(APIError) in throw .signedOut }
        let auth = APIAuthService(client: client, tokens: tokens)

        let session = try await auth.signInWithGoogle(GoogleCredential(idToken: String(repeating: "t", count: 30), rawNonce: "n-1"))

        #expect(session.isNewUser)
        #expect(await tokens.isSignedIn)
        #expect(TokenManager.storedSession(in: store)?.refreshToken == "ref")
        #expect(StubURLProtocol.requests(for: host).count == 1)
        let body = try #require(recorder.last.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["idToken": String(repeating: "t", count: 30), "nonce": "n-1"])
    }

    @Test func anInvalidTokenIsASignInError() async {
        let (client, _) = StubURLProtocol.makeClient { _ in
            .json(401, #"{"error":{"code":"AUTH_INVALID_TOKEN","message":"Invalid Google ID token"}}"#)
        }
        let tokens = TokenManager(store: InMemorySecureStore()) { _ throws(APIError) in throw .signedOut }
        let viewModel = SignInViewModel(mode: .signUp, auth: APIAuthService(client: client, tokens: tokens),
                                        google: MockGoogleSignIn(delay: .zero)) { _ in Issue.record("signed in") }
        await viewModel.signInWithGoogle()
        #expect(viewModel.error?.title == "Sign in with Google didn’t work")
        #expect(await !tokens.isSignedIn)
    }
}
