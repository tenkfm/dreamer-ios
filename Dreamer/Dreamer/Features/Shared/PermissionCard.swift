import SwiftUI

/// A permission explained in our words before the system asks (microphone, tracking).
struct PermissionCard<Actions: View>: View {
    var systemImage: String
    var title: String
    var message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DS.Palette.icon)
                    .frame(width: 54, height: 54)
                    .softFill(Circle(), opacity: 0.7)
                    .accessibilityHidden(true)
                Text(title).textStyle(.heading).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                Text(message)
                    .textStyle(.secondary, color: DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 4) { actions() }.padding(.top, 6)
            }
            .padding(.horizontal, DS.Space.cardPaddingLarge)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .glassCard(radius: DS.Radius.cardLarge, style: .selected)
            .padding(.horizontal, DS.Space.screen)
            .padding(.bottom, 12)
        }
    }
}
