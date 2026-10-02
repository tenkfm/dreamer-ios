import Foundation

/// What a screen shows when an API call fails: one state per error code, so no failure ends as an
/// empty screen or a crash.
struct ErrorState: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case offline, timeout, paywall, rateLimited, signIn, linkExpired, notFound, conflict,
             dreamFailed, voiceUnavailable, providerUnavailable, verificationFailed, outdatedApp, serverError
    }

    enum Action: Equatable, Sendable {
        /// Try the same thing again (optionally not before `retryAfter`).
        case retry
        case openPaywall
        case signIn
        case requestNewLink
        /// Nothing to do but acknowledge.
        case dismiss
    }

    var kind: Kind
    var title: String
    var message: String
    var action: Action
    /// When trying again makes sense (rate limits).
    var retryAfter: Date?

    var id: String { "\(kind)-\(title)" }

    init(kind: Kind, title: String, message: String, action: Action, retryAfter: Date? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.action = action
        self.retryAfter = retryAfter
    }

    init(_ error: APIError, now: Date = .now, calendar: Calendar = .current) {
        switch error {
        case .offline:
            self.init(kind: .offline, title: String(localized: "You’re offline"),
                      message: String(localized: "Your dreams are safe on this iPhone and will sync when you’re back online."), action: .retry)
        case .timeout:
            self.init(kind: .timeout, title: String(localized: "This is taking too long"),
                      message: String(localized: "Check your connection and try again."), action: .retry)
        case .signedOut:
            self.init(kind: .signIn, title: String(localized: "Please sign in again"),
                      message: String(localized: "Your session has ended. Sign in to see your journal."), action: .signIn)
        case .notConfigured, .invalidResponse:
            self.init(kind: .outdatedApp, title: String(localized: "Something went wrong"),
                      message: String(localized: "Please update Mooncatch from the App Store and try again."), action: .dismiss)
        case .server(let server):
            self.init(server, now: now, calendar: calendar)
        }
    }

    private init(_ server: APIError.ServerError, now: Date, calendar: Calendar) {
        switch server.code {
        case .premiumRequired:
            self.init(kind: .paywall, title: String(localized: "Unlock your interpretations"),
                      message: String(localized: "Start your free trial to read what your dreams are saying."), action: .openPaywall)
        case .rateLimited, .limitReached:
            let until = server.resetAt ?? server.retryAfter.map { now.addingTimeInterval($0) }
            let message: String
            if server.limit != nil, let until {
                message = String(localized: "You’ve reached today’s limit. Come back after \(Self.time(until, now: now, calendar: calendar)).")
            } else if let until {
                message = String(localized: "Please try again after \(Self.time(until, now: now, calendar: calendar)).")
            } else {
                message = String(localized: "Please try again in a little while.")
            }
            self.init(kind: .rateLimited, title: String(localized: "Let’s take a pause"), message: message, action: .retry, retryAfter: until)
        case .authRequired, .authInvalidToken:
            self.init(kind: .signIn, title: String(localized: "Please sign in again"),
                      message: String(localized: "Your session has ended. Sign in to see your journal."), action: .signIn)
        case .authLinkExpired:
            self.init(kind: .linkExpired, title: String(localized: "This link has expired"),
                      message: String(localized: "Sign-in links work once and for 15 minutes. We can send you a new one."), action: .requestNewLink)
        case .notFound:
            self.init(kind: .notFound, title: String(localized: "This dream is no longer here"),
                      message: String(localized: "It may have been deleted on another device."), action: .dismiss)
        case .conflict:
            self.init(kind: .conflict, title: String(localized: "Almost ready"),
                      message: String(localized: "This is still being prepared. Try again in a moment."), action: .retry)
        case .dreamFailed:
            self.init(kind: .dreamFailed, title: String(localized: "We couldn’t read this dream"),
                      message: String(localized: "Something went wrong while interpreting it. Let’s try again."), action: .retry)
        case .ttsUnavailable:
            self.init(kind: .voiceUnavailable, title: String(localized: "Voice is resting"),
                      message: String(localized: "We’ll read it aloud with the iPhone voice instead."), action: .dismiss)
        case .providerUnavailable:
            self.init(kind: .providerUnavailable, title: String(localized: "Mooncatch is catching its breath"),
                      message: String(localized: "Please try again in a minute."), action: .retry)
        case .attestationRequired:
            self.init(kind: .verificationFailed, title: String(localized: "We couldn’t verify this app"),
                      message: String(localized: "Please try again. If it keeps happening, reinstall Mooncatch from the App Store."), action: .retry)
        case .validationFailed:
            self.init(kind: .outdatedApp, title: String(localized: "Something went wrong"),
                      message: String(localized: "Please update Mooncatch from the App Store and try again."), action: .dismiss)
        case .internalError:
            self.init(kind: .serverError, title: String(localized: "Something went wrong"),
                      message: String(localized: "It’s on our side. Please try again later."), action: .retry)
        }
    }

    /// "7:00 AM" today, "tomorrow at 7:00 AM" otherwise.
    private static func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        let clock = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_US")))
        return calendar.isDate(date, inSameDayAs: now) ? clock : "tomorrow at \(clock)"
    }
}
