import SwiftUI

/// Our explanation before the notification alert: offered once, on the first Home.
struct ReminderPrePrompt: View {
    var minutes: Int
    var onEnable: () -> Void
    var onDecline: () -> Void

    var body: some View {
        ZStack {
            // A modal over Home: dimmed, not blurred, so the screen stays visible behind the card.
            DS.Palette.skyDim.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            PermissionCard(systemImage: "bell",
                           title: "Catch tomorrow’s dream",
                           message: "Dreams fade within minutes. A gentle reminder at \(timeText) helps you tell yours while it is still close. You can change the time in Settings.") {
                PrimaryButton(title: "Remind me", systemImage: "bell", action: onEnable)
                TextLinkButton(title: "Not now", action: onDecline)
            }
        }
    }

    private var timeText: String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    ZStack {
        SkyBackground(kind: .full)
        ReminderPrePrompt(minutes: 450, onEnable: {}, onDecline: {})
    }
}
