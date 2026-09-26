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

    /// Resolves to `day` in the light appearance and `night` in night mode (dark appearance).
    init(day: Color, night: Color) {
        self.init(UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? night : day)
        })
    }

    init(day: UInt32, night: UInt32) {
        self.init(day: Color(hex: day), night: Color(hex: night))
    }
}

/// Design tokens from docs/02-design-system.md. Feature code uses only these values.
/// Colors are adaptive: day values follow the design, night values the deep-navy night mode.
enum DS {
    enum Palette {
        static let background      = Color(day: 0xEEF4FB, night: 0x0F1833)
        static let textPrimary     = Color(day: 0x1E2A4A, night: 0xEDF1FB)
        static let textSecondary   = Color(day: 0x3A4666, night: 0xC4CDE4)
        static let textTertiary    = Color(day: 0x4B587A, night: 0x9FAACA)
        static let overline        = Color(day: 0x3D4A6B, night: 0xB4BFDB)
        static let icon            = Color(day: 0x5670A3, night: 0xA9BDEF)
        static let iconSoft        = Color(day: 0x7FA2DC, night: 0x8FB0EA)
        static let accent          = Color(day: 0x3F5E9C, night: 0xA3BBF4)
        static let cta             = Color(day: 0x2E4677, night: 0x4A67B3)
        static let peach           = Color(hex: 0xF2A488)
        static let tabInactive     = Color(day: 0x8392B4, night: 0x7D89AB)
        static let segmentInactive = Color(day: 0x5B6785, night: 0x9AA5C2)
        static let destructive     = Color(day: 0xB4453C, night: 0xF08A80)
        static let recordDot       = Color(hex: 0xE9826A)
        /// Pure white: text and glyphs over the sky, CTA labels, the logo.
        static let white           = Color.white
        /// Raised opaque surfaces: pills, the selected tab / segment, check circles.
        static let surface         = Color(day: 0xFFFFFF, night: 0x2A3866)
        /// Text on pastel fills (emotion chips, peach badge); dark in both appearances.
        static let ink             = Color(hex: 0x1E2A4A)
        /// Dividers inside glass groups.
        static let hairline        = Color(day: .white.opacity(0.7), night: .white.opacity(0.08))
        /// Empty part of progress tracks and rings.
        static let track           = Color(day: .white.opacity(0.55), night: .white.opacity(0.16))
        /// Unselected chip fill.
        static let chipFill        = Color(day: .white.opacity(0.6), night: .white.opacity(0.06))

        /// Soft blue used for every shadow: rgb(80,110,170). Near-black at night.
        static let shadow          = Color(day: 0x506EAA, night: 0x03081A)
        static let ctaShadow       = Color(day: 0x2E4677, night: 0x03081A)
        /// Orb drop shadow rgb(70,105,170).
        static let orbShadow       = Color(day: 0x4669AA, night: 0x03081A)
        /// Text shadow for white text over the sky: rgb(70,110,180).
        static let skyTextShadow   = Color(day: 0x466EB4, night: 0x0A1230)
        /// Neutral line color rgb(90,110,150) used for radio rings, chip borders, switch off.
        static let line            = Color(day: 0x5A6E96, night: 0x8D9CC4)
        /// Empty week-day ring rgb(130,150,190).
        static let weekRing        = Color(day: 0x8296BE, night: 0x6F7EA8)
        /// Bottom sheet fill rgb(247,250,254) and its shadow rgb(60,90,150).
        static let sheetFill       = Color(day: 0xF7FAFE, night: 0x16213F)
        static let sheetShadow     = Color(day: 0x3C5A96, night: 0x03081A)
        /// Veil laid over the sky behind the Details sheet.
        static let skyDim          = Color(day: 0x2E4677, night: 0x03081A)
        /// Mid stops of the sky fades.
        static let fadeTop         = Color(day: 0xF1F4F8, night: 0x152044)
        static let fadeFull        = Color(day: 0xF1F5FA, night: 0x152044)

        /// White orb by day, a soft moon at night.
        static let orbGradient = RadialGradient(
            stops: [
                .init(color: Color(day: 0xFFFFFF, night: 0xF1F4FD), location: 0),
                .init(color: Color(day: 0xF6F9FE, night: 0xD8E1F6), location: 0.7),
                .init(color: Color(day: 0xE9F0FA, night: 0xB9C8EB), location: 1)
            ],
            center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 70)
    }

    enum Emotion {
        static let anxiety   = Color(hex: 0xF8CFB2)
        static let confusion = Color(hex: 0xDCD3F8)
        static let calm      = Color(hex: 0xC4E2F4)
        static let joy       = Color(hex: 0xF9DF98)
        static let fear      = Color(hex: 0xF6C1C1)
    }

    /// Third-party sign-in buttons wear their owner's branding, not the Dreamer palette: Google
    /// rejects a restyled button, and its guidelines fix these fills, strokes and text colors for
    /// the light and dark themes (developers.google.com/identity/branding-guidelines).
    enum Brand {
        static let googleFill   = Color(day: 0xFFFFFF, night: 0x131314)
        static let googleStroke = Color(day: 0x747775, night: 0x8E918F)
        static let googleText   = Color(day: 0x1F1F1F, night: 0xE3E3E3)
        /// The system face at the size of the Sign in with Apple title above it, so the two
        /// buttons read as a pair (Roboto would be one more font bundled for one label).
        static let signInFont   = Font.system(size: 19, weight: .medium)
    }

    // MARK: - Spacing / radii / sizes

    enum Space {
        static let screen: CGFloat = 22      // side margin for cards and headers
        static let cta: CGFloat = 24         // side margin for bottom CTA blocks
        static let text: CGFloat = 32        // side margin for centered onboarding text
        static let stack: CGFloat = 10       // gap between stacked cards / options
        static let section: CGFloat = 22     // gap between sections
        static let cardPadding: CGFloat = 16
        static let cardPaddingLarge: CGFloat = 18
        /// Distance from the top safe area edge to the header buttons.
        static let headerTop: CGFloat = 6
        /// Bottom content inset on tab screens so the last row clears the floating tab bar.
        static let tabBarClearance: CGFloat = 110
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
        static let tabBarBottom: CGFloat = 24
        static let heroHeight: CGFloat = 380
        static let heroFade: CGFloat = 200
        /// Top sky: the fade runs from `topSkyFadeStart` to `topSkyHeight`, where it is fully opaque,
        /// so the image edge is always hidden under the background.
        static let topSkyFadeStart: CGFloat = 150
        static let topSkyHeight: CGFloat = 380
    }
}

// MARK: - Fonts

/// One place to swap the UI family. Default = Quicksand ("Light" weight set from the design).
enum DreamerFont {
    enum Weight { case light, regular, medium, semibold, bold }

    static func postScriptName(_ weight: Weight) -> String {
        switch weight {
        case .light:    "Quicksand-Light"
        case .regular:  "Quicksand-Regular"
        case .medium:   "Quicksand-Medium"
        case .semibold: "Quicksand-SemiBold"
        case .bold:     "Quicksand-Bold"
        }
    }

    /// Scales with Dynamic Type relative to `textStyle`.
    static func ui(_ size: CGFloat, _ weight: Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(postScriptName(weight), size: size, relativeTo: textStyle)
    }

    /// Does not scale. For chrome that must keep its geometry (tab bar, pills).
    static func fixed(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(postScriptName(weight), fixedSize: size)
    }

    static func logo(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBoldItalic", fixedSize: size)
    }
}

/// Type scale from docs/02-design-system.md section 3.
enum TextStyle {
    case logoLarge, logo, display, title, heading, lead, bodyStrong, body, bodyLong, button, link, secondary, label, small, overline

    var font: Font {
        switch self {
        case .logoLarge:       DreamerFont.logo(44)
        case .logo:            DreamerFont.logo(28)
        case .display:         DreamerFont.ui(26, .medium, relativeTo: .title)
        case .title:           DreamerFont.ui(24, .medium, relativeTo: .title2)
        case .heading:         DreamerFont.ui(18, .medium, relativeTo: .headline)
        case .lead:            DreamerFont.ui(17, .regular, relativeTo: .body)
        case .bodyStrong:      DreamerFont.ui(15, .medium, relativeTo: .body)
        case .body, .bodyLong: DreamerFont.ui(15, .regular, relativeTo: .body)
        case .button:          DreamerFont.ui(16, .medium, relativeTo: .body)
        case .link:            DreamerFont.ui(14, .regular, relativeTo: .callout)
        case .secondary:       DreamerFont.ui(13, .regular, relativeTo: .subheadline)
        case .label:           DreamerFont.ui(12, .regular, relativeTo: .caption)
        case .small:           DreamerFont.ui(11, .regular, relativeTo: .caption2)
        case .overline:        DreamerFont.ui(11, .medium, relativeTo: .caption2)
        }
    }

    var size: CGFloat {
        switch self {
        case .logoLarge: 44
        case .logo: 28
        case .display: 26
        case .title: 24
        case .heading: 18
        case .lead: 17
        case .bodyStrong, .body, .bodyLong: 15
        case .button: 16
        case .link: 14
        case .secondary: 13
        case .label: 12
        case .small, .overline: 11
        }
    }

    /// Target line height in pt (nil = default).
    var lineHeight: CGFloat? {
        switch self {
        case .logoLarge: 52
        case .logo: 36
        case .display: 32
        case .title: 30
        case .heading: 24
        case .lead: 27
        case .bodyStrong, .body: 21
        case .bodyLong: 23
        case .secondary: 18
        case .label: 16
        case .small, .overline: 14
        case .button, .link: nil
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: -0.3
        case .title: -0.2
        case .overline: 1.4
        default: 0
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
        modifier(SkyTextShadow())
    }
}

/// White text on the sky: a soft blue shadow, denser with Increase Contrast so the text stays
/// readable over the brightest clouds.
private struct SkyTextShadow: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if contrast == .increased {
            content
                .shadow(color: DS.Palette.skyTextShadow.opacity(0.85), radius: 3, x: 0, y: 1)
                .shadow(color: DS.Palette.skyTextShadow.opacity(0.6), radius: 8, x: 0, y: 1)
        } else {
            content.shadow(color: DS.Palette.skyTextShadow.opacity(0.4), radius: 7, x: 0, y: 1)
        }
    }
}
