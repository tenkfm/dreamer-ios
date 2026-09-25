import AuthenticationServices
import CryptoKit
import Foundation

/// Sign in with Apple plumbing: the nonce and the credential mapping.
/// Apple gets the SHA-256 of a random nonce and puts it in the identity token; the backend receives
/// the raw nonce and checks that it hashes to the token's claim, so a stolen token cannot be replayed.
enum AppleSignIn {
    /// Prepares a request and returns the raw nonce to send to the backend with the credential.
    static func prepare(_ request: ASAuthorizationAppleIDRequest) -> String {
        let nonce = randomNonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        return nonce
    }

    static func credential(from authorization: ASAuthorization, rawNonce: String) -> AppleCredential? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else { return nil }
        return AppleCredential(
            identityToken: identityToken,
            authorizationCode: apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
            rawNonce: rawNonce,
            givenName: apple.fullName?.givenName,
            familyName: apple.fullName?.familyName
        )
    }

    /// True when the user closed the Apple sheet (nothing to report).
    static func isCancellation(_ error: any Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
