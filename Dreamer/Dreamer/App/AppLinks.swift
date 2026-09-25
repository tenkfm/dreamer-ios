import Foundation

/// External links (placeholders until the legal pages are live).
enum AppLinks {
    static let terms = URL(string: "https://dreamer.app/terms")!
    static let privacy = URL(string: "https://dreamer.app/privacy")!
    static let support = URL(string: "mailto:support@dreamer.app")!
}

/// Links that open the app: universal links on the API host (Associated Domains `applinks:`).
enum DeepLink: Equatable, Sendable {
    /// `https://<api host>/auth/verify?token=...` from the sign-in email.
    case emailSignIn(token: String)

    /// Parses a URL the app was opened with. Only the API host of this build is trusted, so a
    /// link for staging never signs in to production and vice versa.
    init?(url: URL, apiHost: String?) {
        guard url.scheme == "https", let host = url.host(), host == apiHost else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.path() {
        case "/auth/verify", "/auth/verify/":
            guard let token = components?.queryItems?.first(where: { $0.name == "token" })?.value,
                  !token.isEmpty else { return nil }
            self = .emailSignIn(token: token)
        default:
            return nil
        }
    }
}
