import Foundation

/// A place to get help, shown on the support screen of a crisis-flagged dream.
struct SupportResource: Identifiable, Equatable, Sendable {
    enum Contact: Equatable, Sendable {
        case phone(String)
        case web(URL)
    }

    var name: String
    /// When or how it helps ("24/7, free and confidential").
    var detail: String
    var contact: Contact

    var id: String { name }

    /// What the button opens.
    var url: URL? {
        switch contact {
        case .phone(let number):
            URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" })
        case .web(let url):
            url
        }
    }
}

/// The support screen shown instead of a mystical reading when the backend flags a dream
/// (self-harm, abuse). Supportive, never diagnostic: no medical promises.
struct SupportContent: Equatable, Sendable {
    var title: String
    var message: String
    /// Said on every support screen, with or without local resources.
    var emergencyNote: String
    var resources: [SupportResource]
}

/// Support copy and help resources for the user's country. Both need approval (the texts and the
/// list of services per country come from Tony, blocker IOS-05.2), so they live behind this
/// protocol and the approved version replaces `PendingSupportContent` without touching the screen.
protocol SupportContentProvider: Sendable {
    func content(for region: Locale.Region?) -> SupportContent
}

/// Until the copy is approved: a neutral draft and no country-specific services (a wrong phone
/// number on a crisis screen is worse than none), only the pointer to local emergency services.
struct PendingSupportContent: SupportContentProvider {
    func content(for region: Locale.Region?) -> SupportContent {
        SupportContent(
            title: String(localized: "This dream sounds heavy"),
            message: String(localized: "Some dreams carry more than a reading can hold. You don’t have to go through this alone - talking to someone you trust, or to a professional, can help."),
            emergencyNote: String(localized: "If you are in danger or thinking about hurting yourself, call your local emergency number now."),
            resources: []
        )
    }
}
