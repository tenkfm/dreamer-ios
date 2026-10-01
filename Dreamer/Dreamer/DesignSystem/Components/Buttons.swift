import SwiftUI

// MARK: - Press style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.press, value: configuration.isPressed)
    }
}

// MARK: - Primary

/// Visual of the primary CTA. Shared by `PrimaryButton` and `ShareLink` labels.
struct PrimaryButtonLabel: View {
    var title: String
    var systemImage: String? = nil
    var isLoading = false
    /// White with dark text, for a dark background (the paywall modal).
    var light = false

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(light ? DS.Palette.ink : .white)
            } else {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .regular))
                }
                Text(title).font(TextStyle.button.font).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(light ? DS.Palette.ink : DS.Palette.white)
        .frame(maxWidth: .infinity)
        .frame(height: DS.Size.primaryButton)
        .background(Capsule().fill(light ? DS.Palette.white : DS.Palette.cta))
        .shadow(color: DS.Palette.ctaShadow.opacity(0.3), radius: 15, x: 0, y: 14)
        .contentShape(Capsule())
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var isLoading = false
    var light = false
    var action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            PrimaryButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading, light: light)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(title)
    }
}

// MARK: - Secondary

struct TextLinkButton: View {
    var title: String
    var color: Color = DS.Palette.textPrimary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.link, color: color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DS.Size.linkButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// White capsule with a 12 pt label ("See the pattern", "Make this my main lens").
struct PillButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(DreamerFont.fixed(12)).foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(DS.Palette.surface))
                .shadow(color: DS.Palette.shadow.opacity(0.15), radius: 6, x: 0, y: 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 46 pt round glass button with a thin icon.
struct GlassIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var size: CGFloat = DS.Size.iconButton
    var style: GlassStyle = .card
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassIconLabel(systemImage: systemImage, size: size, style: style)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Visual of `GlassIconButton`. Shared with `ShareLink` labels.
struct GlassIconLabel: View {
    var systemImage: String
    var size: CGFloat = DS.Size.iconButton
    var style: GlassStyle = .card

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .light))
            .foregroundStyle(DS.Palette.icon)
            .frame(width: size, height: size)
            .glassCircle(style: style)
    }
}

/// White text button over the sky ("Skip").
struct SkyTextButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.secondary, color: DS.Palette.white)
                .skyTextShadow()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logo

struct Logo: View {
    var large = false
    /// White with a soft shadow over a picture; the text color on the plain background.
    var onSky = true

    var body: some View {
        Text("Dreamer")
            .font(large ? TextStyle.logoLarge.font : TextStyle.logo.font)
            .foregroundStyle(onSky ? DS.Palette.white : DS.Palette.textPrimary)
            .shadow(color: DS.Palette.skyTextShadow.opacity(onSky ? 0.35 : 0), radius: 7, x: 0, y: 2)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Buttons") {
    ZStack {
        SkyBackground(kind: .full)
        VStack(spacing: 20) {
            Logo(large: true)
            HStack {
                GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {}
                Spacer()
                SkyTextButton(title: "Skip") {}
            }
            PillButton(title: "See the pattern") {}
            PrimaryButton(title: "Interpret my dream", systemImage: "sparkle") {}
            PrimaryButton(title: "Loading", isLoading: true) {}
            TextLinkButton(title: "I already have an account") {}
        }
        .padding(DS.Space.cta)
    }
}
