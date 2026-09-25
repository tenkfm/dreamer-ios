import Foundation
import Testing
@testable import Dreamer

struct DeepLinkTests {
    private let host = "api-staging-0ea4.up.railway.app"

    @Test func emailSignInLinkIsParsed() throws {
        let url = try #require(URL(string: "https://\(host)/auth/verify?token=abc123"))
        #expect(DeepLink(url: url, apiHost: host) == .emailSignIn(token: "abc123"))
    }

    @Test func otherHostsPathsAndEmptyTokensAreIgnored() throws {
        for link in ["https://evil.example/auth/verify?token=abc",
                     "http://\(host)/auth/verify?token=abc",
                     "https://\(host)/auth/verify",
                     "https://\(host)/auth/verify?token=",
                     "https://\(host)/somewhere?token=abc"] {
            let url = try #require(URL(string: link))
            #expect(DeepLink(url: url, apiHost: host) == nil, "\(link)")
        }
        let url = try #require(URL(string: "https://\(host)/auth/verify?token=abc"))
        #expect(DeepLink(url: url, apiHost: nil) == nil)
    }
}

@MainActor
struct EmailLinkFlowTests {
    @Test func coldStartLinkWaitsForTheAccountStep() {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.handle(.emailSignIn(token: "t1"))

        #expect(appState.consumeEmailSignInToken() == "t1")
        #expect(appState.consumeEmailSignInToken() == nil)
    }

    @Test func linkIsIgnoredWhenAlreadySignedIn() {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.handle(.emailSignIn(token: "t1"))
        #expect(appState.pendingDeepLink == nil)
    }

    @Test func openingALinkMovesOnboardingToSignIn() {
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = OnboardingViewModel(appState: appState, step: .understand)
        viewModel.openEmailLink()
        #expect(viewModel.step == .account)
    }

    @Test func validLinkSignsIn() async {
        var session: AuthSession?
        let viewModel = SignInViewModel(mode: .signIn, auth: MockAuthService(nextUserIsNew: false, delay: .zero)) { session = $0 }
        await viewModel.verifyLink(token: "good")
        #expect(session?.isNewUser == false)
        #expect(viewModel.error == nil)
    }

    @Test func expiredLinkSendsANewOneToTheKnownAddress() async {
        let auth = MockAuthService(delay: .zero)
        let viewModel = SignInViewModel(mode: .signIn, auth: auth) { _ in }
        viewModel.email = "anna@example.com"

        await viewModel.verifyLink(token: "expired")
        #expect(viewModel.error?.kind == .linkExpired)

        await viewModel.performErrorAction()
        #expect(viewModel.phase == .checkInbox(email: "anna@example.com"))
        #expect(await auth.sentLinks == ["anna@example.com"])
    }
}
