import SwiftUI

/// The outcome of a target action, felt: a view model sets one when it knows how the action ended
/// (saved, shared, bought, deleted, failed) and its view plays it with `.haptic(_:)`. Each event is
/// new, so the same outcome twice plays twice. Navigation gets none; taps on primary buttons,
/// selections, toggles and recording have their own feedback where they are drawn.
struct HapticEvent: Equatable {
    enum Kind {
        case success, warning, error
        /// An action accepted that finishes later (a new image is being painted).
        case impact
    }

    let kind: Kind
    private let id = UUID()

    init(_ kind: Kind) { self.kind = kind }
}

extension View {
    func haptic(_ event: HapticEvent?) -> some View {
        sensoryFeedback(trigger: event) { _, event in
            switch event?.kind {
            case .success: .success
            case .warning: .warning
            case .error: .error
            case .impact: .impact(weight: .medium)
            case nil: nil
            }
        }
    }
}
