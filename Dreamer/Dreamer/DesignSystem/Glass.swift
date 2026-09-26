import SwiftUI

// NOTE on shadows: CSS "0 10px 28px" (blur 28) ~= SwiftUI .shadow(radius: 14, y: 10).
// SwiftUI radius is roughly half the CSS blur value.

enum GlassStyle {
    case card          // white 36%, border white 70%, shadow 12% blur 28 y 10
    case tabBar        // white 42%, border white 75%, shadow 16% blur 30 y 12
    case selected      // white 82%, border 1.5 white, shadow 18% blur 28 y 12
    case option        // white 36%, border white 70%, shadow 8% blur 22 y 8

    /// At night the same white glass is much thinner, or it turns into grey slabs on navy.
    func fill(night: Bool) -> Double {
        switch self {
        case .card, .option: night ? 0.07 : 0.36
        case .tabBar: night ? 0.10 : 0.42
        case .selected: night ? 0.16 : 0.82
        }
    }

    func border(night: Bool) -> Double {
        switch self {
        case .card, .option: night ? 0.12 : 0.7
        case .tabBar: night ? 0.16 : 0.75
        case .selected: night ? 0.3 : 1
        }
    }

    func shadowOpacity(night: Bool) -> Double {
        let day: Double = switch self { case .card: 0.12; case .tabBar: 0.16; case .selected: 0.18; case .option: 0.08 }
        return night ? day * 2.5 : day
    }

    var borderWidth: CGFloat { self == .selected ? 1.5 : 1 }
    var shadowRadius: CGFloat { switch self { case .card, .selected: 14; case .tabBar: 15; case .option: 11 } }
    var shadowY: CGFloat { switch self { case .card: 10; case .tabBar, .selected: 12; case .option: 8 } }
}

extension EnvironmentValues {
    /// Long lists (Journal, Library): no blur layer per card. The blur is only 30 % strong, so the
    /// cards look the same, but dozens of live blurs cost frames while scrolling on older iPhones.
    @Entry var lightweightGlass = false
}

struct GlassBackground<S: InsettableShape>: ViewModifier {
    var shape: S
    var style: GlassStyle = .card

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lightweightGlass) private var lightweightGlass

    func body(content: Content) -> some View {
        let night = colorScheme == .dark
        content
            .background {
                ZStack {
                    // Light blur of what is behind. Kept subtle so the card does not turn grey.
                    if lightweightGlass {
                        shape.fill(Color.white.opacity(night ? 0.02 : 0.1))
                    } else {
                        shape.fill(.ultraThinMaterial).opacity(0.3)
                    }
                    // At night a navy veil keeps light glyphs readable over bright dream images;
                    // on the night background itself it is invisible.
                    if night { shape.fill(DS.Palette.background.opacity(0.4)) }
                    shape.fill(Color.white.opacity(style.fill(night: night)))
                }
                .shadow(color: DS.Palette.shadow.opacity(style.shadowOpacity(night: night)),
                        radius: style.shadowRadius, x: 0, y: style.shadowY)
            }
            .overlay(shape.strokeBorder(Color.white.opacity(style.border(night: night)), lineWidth: style.borderWidth))
            .contentShape(shape)
            // Do not clipShape here: it would cut off the shadow. Clip images inside the card instead.
    }
}

/// Inner soft fill (icon circles inside cards, player bar): white 60-70 % by day, a faint veil at night.
private struct SoftFill<S: Shape>: ViewModifier {
    var shape: S
    var opacity: Double

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(shape.fill(Color.white.opacity(colorScheme == .dark ? opacity * 0.15 : opacity)))
    }
}

extension View {
    func glassCard(radius: CGFloat = DS.Radius.card, style: GlassStyle = .card) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), style: style))
    }

    func glassCapsule(style: GlassStyle = .card) -> some View {
        modifier(GlassBackground(shape: Capsule(style: .continuous), style: style))
    }

    func glassCircle(style: GlassStyle = .card) -> some View {
        modifier(GlassBackground(shape: Circle(), style: style))
    }

    /// Inner soft fill (icon circles inside cards, player bar), no border.
    func softFill<S: Shape>(_ shape: S, opacity: Double = 0.6) -> some View {
        modifier(SoftFill(shape: shape, opacity: opacity))
    }
}
