import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum DS {
    enum Palette {
        static let background      = Color(hex: 0xEEF4FB)
        static let textPrimary     = Color(hex: 0x1E2A4A)
        static let textSecondary   = Color(hex: 0x3A4666)
        static let textTertiary    = Color(hex: 0x4B587A)
        static let overline        = Color(hex: 0x3D4A6B)
        static let icon            = Color(hex: 0x5670A3)
        static let iconSoft        = Color(hex: 0x7FA2DC)
        static let accent          = Color(hex: 0x3F5E9C)
        static let cta             = Color(hex: 0x2E4677)
        static let peach           = Color(hex: 0xF2A488)
        static let tabInactive     = Color(hex: 0x8392B4)
        static let segmentInactive = Color(hex: 0x5B6785)
        static let destructive     = Color(hex: 0xB4453C)
        static let recordDot       = Color(hex: 0xE9826A)

        /// Soft blue used for every shadow: rgb(80,110,170).
        static let shadow          = Color(hex: 0x506EAA)
        static let ctaShadow       = Color(hex: 0x2E4677)
        /// Text shadow for white text over the sky: rgb(70,110,180).
        static let skyTextShadow   = Color(hex: 0x466EB4)
        /// Neutral line color rgb(90,110,150) used for radio rings, chip borders, switch off.
        static let line            = Color(hex: 0x5A6E96)

        static let orbGradient = RadialGradient(
            colors: [.white, Color(hex: 0xF6F9FE), Color(hex: 0xE9F0FA)],
            center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 60)
    }

    enum Emotion {
        static let anxiety   = Color(hex: 0xF8CFB2)
        static let confusion = Color(hex: 0xDCD3F8)
        static let calm      = Color(hex: 0xC4E2F4)
        static let joy       = Color(hex: 0xF9DF98)
        static let fear      = Color(hex: 0xF6C1C1)
    }

    // MARK: - Spacing / radii

    enum Space {
        static let screen: CGFloat = 22      // side margin for cards and headers
        static let cta: CGFloat = 24         // side margin for bottom CTA blocks
        static let text: CGFloat = 32        // side margin for centered onboarding text
        static let stack: CGFloat = 10       // gap between stacked cards / options
        static let section: CGFloat = 22     // gap between sections
        static let cardPadding: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 24
        static let cardLarge: CGFloat = 26
        static let option: CGFloat = 22
        static let tile: CGFloat = 16
        static let sheet: CGFloat = 32
    }

    enum Size {
        static let primaryButton: CGFloat = 56
        static let linkButton: CGFloat = 40
        static let iconButton: CGFloat = 46
        static let tabBarHeight: CGFloat = 62
        static let tabBarInset: CGFloat = 26
    }
}

// MARK: - Fonts

/// One place to swap the UI family. Default = Quicksand ("Light" weight set from the design).
enum DreamerFont {
    enum Weight { case light, regular, medium, semibold, bold }

    static func ui(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .light:    name = "Quicksand-Light"
        case .regular:  name = "Quicksand-Regular"
        case .medium:   name = "Quicksand-Medium"
        case .semibold: name = "Quicksand-SemiBold"
        case .bold:     name = "Quicksand-Bold"
        }
        return .custom(name, size: size)
    }

    static func logo(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBoldItalic", size: size)
    }
}

/// Type scale from docs/02-design-system.md section 3.
enum TextStyle {
    case logoLarge, logo, display, title, heading, bodyStrong, body, bodyLong, button, link, secondary, label, small, overline

    var font: Font {
        switch self {
        case .logoLarge:  return DreamerFont.logo(44)
        case .logo:       return DreamerFont.logo(28)
        case .display:    return DreamerFont.ui(26, .medium)
        case .title:      return DreamerFont.ui(24, .medium)
        case .heading:    return DreamerFont.ui(18, .medium)
        case .bodyStrong: return DreamerFont.ui(15, .medium)
        case .body, .bodyLong: return DreamerFont.ui(15, .regular)
        case .button:     return DreamerFont.ui(16, .medium)
        case .link:       return DreamerFont.ui(14, .regular)
        case .secondary:  return DreamerFont.ui(13, .regular)
        case .label:      return DreamerFont.ui(12, .regular)
        case .small:      return DreamerFont.ui(11, .regular)
        case .overline:   return DreamerFont.ui(11, .medium)
        }
    }

    var size: CGFloat {
        switch self {
        case .logoLarge: return 44
        case .logo: return 28
        case .display: return 26
        case .title: return 24
        case .heading: return 18
        case .bodyStrong, .body, .bodyLong: return 15
        case .button: return 16
        case .link: return 14
        case .secondary: return 13
        case .label: return 12
        case .small, .overline: return 11
        }
    }

    /// Target line height in pt (nil = default).
    var lineHeight: CGFloat? {
        switch self {
        case .logoLarge: return 52
        case .logo: return 36
        case .display: return 32
        case .title: return 30
        case .heading: return 24
        case .bodyStrong, .body: return 21
        case .bodyLong: return 23
        case .secondary: return 18
        case .label: return 16
        case .small, .overline: return 14
        default: return nil
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: return -0.3
        case .title: return -0.2
        case .overline: return 1.4
        default: return 0
        }
    }
}

extension View {
    /// Applies font, tracking and approximate line height of a design-system text style.
    func textStyle(_ style: TextStyle, color: Color = DS.Palette.textPrimary) -> some View {
        let extra = max(0, (style.lineHeight ?? style.size * 1.2) - style.size * 1.2)
        return self
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(extra)
            .foregroundStyle(color)
    }

    /// Soft blue shadow used for white text over the sky.
    func skyTextShadow() -> some View {
        shadow(color: DS.Palette.skyTextShadow.opacity(0.4), radius: 7, x: 0, y: 1)
    }
}
