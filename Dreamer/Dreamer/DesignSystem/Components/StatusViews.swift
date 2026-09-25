import SwiftUI

/// Glass capsule pinned under the status bar while the device is offline.
struct OfflineBanner: View {
    var message = "You’re offline. Your dreams are saved and will sync."

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.Palette.icon)
            Text(message)
                .font(DreamerFont.ui(12, relativeTo: .caption))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassCapsule(style: .selected)
        .padding(.horizontal, DS.Space.screen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Glass card for a failed load or action: icon, title, message and one action.
struct ErrorStateCard: View {
    var systemImage = "cloud.moon"
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.Palette.icon)
                .frame(width: 54, height: 54)
                .softFill(Circle(), opacity: 0.6)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.heading)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .textStyle(.secondary, color: DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PillButton(title: actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, DS.Space.cardPaddingLarge)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.cardLarge)
    }
}

#Preview("Status") {
    ZStack {
        SkyBackground(kind: .top)
        VStack(spacing: 24) {
            OfflineBanner()
            ErrorStateCard(title: "Let’s take a pause",
                           message: "You’ve reached today’s limit. Come back after 12:00 AM.",
                           actionTitle: "Try again") {}
                .padding(.horizontal, DS.Space.screen)
        }
    }
}
