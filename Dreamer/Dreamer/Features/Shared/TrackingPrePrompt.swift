import SwiftUI

/// Our explanation before the App Tracking Transparency alert. One way on: the system alert is
/// where the user says yes or no (App Review 5.1.1: no incentive, no look-alike of the alert).
struct TrackingPrePrompt: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            // A modal over Home: dimmed, not blurred, so the screen stays visible behind the card.
            DS.Palette.skyDim.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            PermissionCard(systemImage: "sparkles",
                           title: "Help Mooncatch find dreamers",
                           message: "Next, iOS asks whether Mooncatch may see which ad brought you here. It helps us spend less on ads and more on Mooncatch. Your dreams are never shared, whatever you choose.") {
                PrimaryButton(title: "Continue", action: onContinue)
            }
        }
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full)
        TrackingPrePrompt {}
    }
}
