import Foundation

/// Build-time configuration. Values come from the xcconfig of the active configuration
/// (Config/*.xcconfig, secrets from Secrets.xcconfig or CI) through Info.plist, so switching
/// environments never needs a code change.
struct AppConfig: Sendable, Equatable {
    enum Environment: String, Sendable {
        case debug, staging, production
    }

    let environment: Environment
    /// Nil when the configuration has no API host (the production domain is not chosen yet).
    let apiBaseURL: URL?
    let revenueCatAPIKey: String?
    let postHogAPIKey: String?
    let postHogHost: URL?
    let sentryDSN: String?
    /// Instagram Stories needs the Meta app id in its share URL; nil hides the Stories button.
    let facebookAppID: String?
    /// Google Sign-In; nil hides the Google button in live builds.
    let googleOAuthClient: GoogleOAuthClient?
    /// Which APNs the device token belongs to (the aps-environment entitlement of the build).
    let pushEnvironment: PushEnvironment

    static let current = AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:])

    init(infoDictionary info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unset build setting stays as the literal "$(NAME)" in Info.plist.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
            return trimmed
        }

        environment = value("DreamerEnvironment").flatMap(Environment.init(rawValue:)) ?? .debug
        // Release has no host until the production domain exists, which leaves a bare "https://".
        apiBaseURL = value("DreamerAPIBaseURL")
            .flatMap(URL.init(string:))
            .flatMap { $0.host()?.isEmpty == false ? $0 : nil }
        revenueCatAPIKey = value("DreamerRevenueCatAPIKey")
        postHogAPIKey = value("DreamerPostHogAPIKey")
        postHogHost = value("DreamerPostHogHost").flatMap(URL.init(string:))
        sentryDSN = value("DreamerSentryDSN")
        facebookAppID = value("DreamerFacebookAppID")
        googleOAuthClient = value("DreamerGoogleClientID").flatMap(GoogleOAuthClient.init(clientID:))
        pushEnvironment = value("DreamerAPSEnvironment") == "production" ? .production : .sandbox
    }
}
