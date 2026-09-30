import Foundation
import GoogleSignIn
import UIKit

/// What Google sign-in hands the app, for `POST /v1/auth/google`. The backend checks the id token
/// against Google (signature, audience = our client ids) and the nonce.
struct GoogleCredential: Sendable, Equatable {
    var idToken: String
    /// Google copies it into the id token as is; the backend checks that they match, so an id token
    /// lifted from another sign-in cannot be replayed.
    var rawNonce: String?
}

enum GoogleSignInError: Error, Equatable, Sendable {
    /// The user closed the sheet or declined on Google's page: nothing to report.
    case cancelled
    case offline
    /// Google's answer was unusable (no id token, an SDK error).
    case failed
}

/// Sign in with Google: shows Google's account picker and returns the id token.
@MainActor
protocol GoogleSignInProvider: Sendable {
    func signIn() async throws(GoogleSignInError) -> GoogleCredential
}

/// The iOS OAuth client id ("<number>-<id>.apps.googleusercontent.com") from `GIDClientID`.
enum GoogleClientID {
    /// Nil for an empty or unset value, or anything but an iOS client id: the SDK raises an
    /// Objective-C exception (a crash) when it has no client id, so the button must stay hidden.
    static func validated(_ value: String?) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard let value, value.hasSuffix(suffix), value.count > suffix.count, !value.contains("/") else { return nil }
        return value
    }
}

/// Google's SDK (GoogleSignIn-iOS). It reads `GIDClientID` from Info.plist and returns through the
/// `REVERSED_CLIENT_ID` URL scheme (`handle(_:)`). Only the id token is used: the SDK is signed out
/// right away, so no Google tokens stay on the device.
struct GoogleSDKSignIn: GoogleSignInProvider {
    func signIn() async throws(GoogleSignInError) -> GoogleCredential {
        guard let presenter = Self.topViewController() else { throw .failed }
        let nonce = AppleSignIn.randomNonce()
        let idToken: String?
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil,
                                                                   additionalScopes: nil, nonce: nonce)
            idToken = result.user.idToken?.tokenString
        } catch {
            throw Self.error(for: error)
        }
        GIDSignIn.sharedInstance.signOut()
        guard let idToken, !idToken.isEmpty else { throw .failed }
        return GoogleCredential(idToken: idToken, rawNonce: nonce)
    }

    /// Google's redirect back into the app; true when it was one.
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    nonisolated static func error(for error: any Error) -> GoogleSignInError {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain, nsError.code == GIDSignInError.canceled.rawValue { return .cancelled }
        if let code = (error as? URLError)?.code,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .dataNotAllowed].contains(code) {
            return .offline
        }
        return .failed
    }

    /// The SDK presents from a view controller; SwiftUI has none to hand, so the topmost one of the
    /// key window is used (a sheet, if one is up).
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Mock mode: every Google sign-in succeeds without the SDK.
struct MockGoogleSignIn: GoogleSignInProvider {
    var delay: Duration = .milliseconds(600)
    var result: Result<GoogleCredential, GoogleSignInError> = .success(
        GoogleCredential(idToken: "mock-google-id-token", rawNonce: "mock-nonce"))

    func signIn() async throws(GoogleSignInError) -> GoogleCredential {
        try? await Task.sleep(for: delay)
        return try result.get()
    }
}
