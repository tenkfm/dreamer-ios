import SwiftUI

/// Covers the app while the journal lock is on and the owner has not authenticated, and in the
/// app switcher: the logo and one way in.
struct LockScreen: View {
    /// Nil in the app switcher (only the cover shows).
    var onUnlock: (() -> Void)?

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 18) {
                Spacer()
                Logo(onSky: false)
                Text("Your journal is locked")
                    .textStyle(.heading)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let onUnlock {
                    PrimaryButton(title: "Unlock", systemImage: "faceid", action: onUnlock)
                        .padding(.horizontal, DS.Space.cta)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

#Preview {
    LockScreen {}
}
