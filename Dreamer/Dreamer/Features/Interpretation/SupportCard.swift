import SwiftUI

/// Shown instead of the reading for a crisis-flagged dream: a calm glass card with the support
/// message, places to get help (when approved for the user's country) and the emergency note.
struct SupportCard: View {
    var content: SupportContent

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                TwinklingSparkle(size: 18).padding(.top, 3)
                Text(content.title)
                    .textStyle(.heading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(content.message)
                .textStyle(.bodyLong)
                .fixedSize(horizontal: false, vertical: true)

            if !content.resources.isEmpty {
                VStack(spacing: 10) {
                    ForEach(content.resources) { resource in
                        resourceRow(resource)
                    }
                }
            }

            Text(content.emergencyNote)
                .textStyle(.secondary, color: DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.cardPaddingLarge)
        .glassCard(radius: DS.Radius.cardLarge)
    }

    private func resourceRow(_ resource: SupportResource) -> some View {
        Button {
            if let url = resource.url { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.name).textStyle(.bodyStrong)
                    Text(resource.detail).textStyle(.secondary, color: DS.Palette.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: resource.contact.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.icon)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(DS.Palette.surface.opacity(0.7)))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(resource.contact.accessibilityHint)
    }
}

private extension SupportResource.Contact {
    var systemImage: String {
        switch self {
        case .phone: "phone"
        case .web: "arrow.up.right"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .phone(let number): "Calls \(number)"
        case .web: "Opens the website"
        }
    }
}

#Preview {
    ZStack {
        DS.Palette.background.ignoresSafeArea()
        SupportCard(content: PendingSupportContent().content(for: nil))
            .padding()
    }
}
