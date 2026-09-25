import Foundation
import Testing
@testable import Dreamer

@MainActor
struct SignInViewModelTests {
    private func makeViewModel(auth: any AuthService = MockAuthService(delay: .zero),
                               analytics: RecordingAnalytics = RecordingAnalytics(),
                               signedIn: @escaping (AuthSession) -> Void = { _ in }) -> SignInViewModel {
        SignInViewModel(mode: .signUp, auth: auth, analytics: analytics, onSignedIn: signedIn)
    }

    @Test func emailValidationCatchesObviousTypos() {
        let viewModel = makeViewModel()
        for bad in ["", "anna", "anna@", "@mail.com", "anna@mail", "anna@mail.", "an na@mail.com"] {
            viewModel.email = bad
            #expect(!viewModel.isEmailValid, "\(bad)")
        }
        viewModel.email = "  anna@example.com "
        #expect(viewModel.isEmailValid)
        #expect(viewModel.trimmedEmail == "anna@example.com")
    }

    @Test func emailLinkLeadsToCheckInboxWithAResendCooldown() async {
        let auth = MockAuthService(delay: .zero)
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(auth: auth, analytics: analytics)
        viewModel.email = "anna@example.com"

        await viewModel.continueWithEmail()

        #expect(viewModel.phase == .checkInbox(email: "anna@example.com"))
        #expect(!viewModel.canResend)
        #expect(await auth.sentLinks == ["anna@example.com"])
        #expect(analytics.events == [.signInStarted(method: .email)])
    }

    @Test func rateLimitedEmailShowsWhenToTryAgain() async {
        let (client, _) = StubURLProtocol.makeClient { _ in
            .json(429, #"{"error":{"code":"RATE_LIMITED","message":"Too many emails","details":{"retryAfterSec":1800}}}"#,
                  headers: ["Retry-After": "1800"])
        }
        let tokens = TokenManager(store: InMemorySecureStore()) { _ throws(APIError) in throw .signedOut }
        let viewModel = makeViewModel(auth: APIAuthService(client: client, tokens: tokens))
        viewModel.email = "anna@example.com"

        await viewModel.continueWithEmail()

        #expect(viewModel.phase == .form)
        #expect(viewModel.error?.kind == .rateLimited)
        #expect(!viewModel.isWorking)
    }

    @Test func appleSignInStoresTheSessionAndReportsIt() async {
        let (client, _) = StubURLProtocol.makeClient { request in
            #expect(request.url?.path() == "/v1/auth/apple")
            return .json(200, """
            {"accessToken":"acc","accessExpiresAt":"2026-09-25T06:27:00.000Z","refreshToken":"ref",
             "refreshExpiresAt":"2026-11-24T06:12:00.000Z","user":{"id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","isNew":true}}
            """)
        }
        let store = InMemorySecureStore()
        let tokens = TokenManager(store: store) { _ throws(APIError) in throw .signedOut }
        var received: AuthSession?
        let viewModel = makeViewModel(auth: APIAuthService(client: client, tokens: tokens)) { received = $0 }

        viewModel.appleSignInStarted()
        await viewModel.signInWithApple(AppleCredential(identityToken: String(repeating: "t", count: 30),
                                                        authorizationCode: "code", rawNonce: "nonce",
                                                        givenName: "Anna", familyName: nil))

        #expect(received?.userID == "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        #expect(received?.isNewUser == true)
        #expect(await tokens.isSignedIn)
        #expect(TokenManager.storedSession(in: store)?.refreshToken == "ref")
        #expect(!viewModel.isWorking)
    }

    @Test func cancelledAppleSheetShowsNothing() {
        let viewModel = makeViewModel()
        viewModel.appleSignInStarted()
        viewModel.appleSignInFailed(cancelled: true)
        #expect(viewModel.error == nil)
        #expect(!viewModel.isWorking)
    }

    @Test func expiredLinkOffersANewOne() async {
        let viewModel = makeViewModel()
        await viewModel.verifyLink(token: "expired")
        #expect(viewModel.error?.action == .requestNewLink)
        #expect(viewModel.phase == .form)
    }

    @Test func nonceIsHashedForApple() {
        #expect(AppleSignIn.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(AppleSignIn.randomNonce().count == 32)
        #expect(AppleSignIn.randomNonce() != AppleSignIn.randomNonce())
    }
}

@MainActor
struct AccountLinkTests {
    actor RecordingPurchases: PurchaseService {
        private(set) var logins: [String?] = []
        func purchase(_ plan: Plan) async throws {}
        func restore() async throws -> Plan? { nil }
        func logIn(userID: String) async { logins.append(userID) }
        func logOut() async { logins.append(nil) }
    }

    @Test func signInAndOutReachEverySDK() async {
        let purchases = RecordingPurchases()
        let analytics = RecordingAnalytics()
        let dependencies = AppDependencies(analytics: analytics, dreamStore: InMemoryDreamStore(seed: []),
                                           analysis: MockDreamAnalysisService(), purchases: purchases,
                                           catalog: MockSymbolCatalog(), imageSaver: MockImageSaver(),
                                           makeSpeechService: { MockSpeechService() },
                                           makeReadAloudService: { MockReadAloudService() })

        await dependencies.linkAccount(userID: "user-1")
        await dependencies.unlinkAccount()

        #expect(await purchases.logins == ["user-1", nil])
        #expect(analytics.identified == ["user-1", nil])
    }
}
