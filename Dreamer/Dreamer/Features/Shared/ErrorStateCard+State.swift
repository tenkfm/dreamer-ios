import SwiftUI

extension ErrorStateCard {
    /// Card for an API failure; `perform` receives the state's action (retry, paywall, sign-in...).
    init(_ state: ErrorState, perform: @escaping (ErrorState.Action) -> Void) {
        self.init(systemImage: state.systemImage, title: state.title, message: state.message,
                  actionTitle: state.actionTitle, action: state.actionTitle == nil ? nil : { perform(state.action) })
    }
}

extension ErrorState {
    var actionTitle: String? {
        switch action {
        case .retry: retryAfter == nil ? String(localized: "Try again") : nil
        case .openPaywall: String(localized: "See plans")
        case .signIn: String(localized: "Sign in")
        case .requestNewLink: String(localized: "Send a new link")
        case .dismiss: nil
        }
    }

    var systemImage: String {
        switch kind {
        case .offline: "wifi.slash"
        case .timeout: "hourglass"
        case .paywall: "sparkles"
        case .rateLimited: "moon.zzz"
        case .signIn, .linkExpired: "person.crop.circle"
        case .notFound: "questionmark.circle"
        case .voiceUnavailable: "speaker.slash"
        default: "cloud.moon"
        }
    }
}
