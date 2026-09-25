import SwiftUI

// NOTE on shadows: CSS "0 10px 28px" (blur 28) ~= SwiftUI .shadow(radius: 14, y: 10).
// SwiftUI radius is roughly half the CSS blur value.

enum GlassStyle {
    case card          // white 36%, border white 70%, shadow 12% blur 28 y 10
    case tabBar        // white 42%, border white 75%, shadow 16% blur 30 y 12
    case selected      // white 82%, border 1.5 white, shadow 18% blur 28 y 12
    case option        // white 36%, border white 70%, shadow 8% blur 22 y 8

    var fill: Double { switch self { case .card, .option: 0.36; case .tabBar: 0.42; case .selected: 0.82 } }
    var border: Double { switch self { case .card, .option: 0.7; case .tabBar: 0.75; case .selected: 1 } }
    var borderWidth: CGFloat { self == .selected ? 1.5 : 1 }
    var shadowOpacity: Double { switch self { case .card: 0.12; case .tabBar: 0.16; case .selected: 0.18; case .option: 0.08 } }
    var shadowRadius: CGFloat { switch self { case .card, .selected: 14; case .tabBar: 15; case .option: 11 } }
    var shadowY: CGFloat { switch self { case .card: 10; case .tabBar, .selected: 12; case .option: 8 } }
}

struct GlassBackground<S: InsettableShape>: ViewModifier {
    var shape: S
    var style: GlassStyle = .card

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Light blur of what is behind. Kept subtle so the card does not turn grey.
                    shape.fill(.ultraThinMaterial).opacity(0.3)
                    shape.fill(Color.white.opacity(style.fill))
                }
                .shadow(color: DS.Palette.shadow.opacity(style.shadowOpacity),
                        radius: style.shadowRadius, x: 0, y: style.shadowY)
            }
            .overlay(shape.strokeBorder(Color.white.opacity(style.border), lineWidth: style.borderWidth))
            .contentShape(shape)
            // Do not clipShape here: it would cut off the shadow. Clip images inside the card instead.
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

    /// Inner soft fill (icon circles inside cards, player bar): white 60-70 %, no border.
    func softFill<S: Shape>(_ shape: S, opacity: Double = 0.6) -> some View {
        background(shape.fill(Color.white.opacity(opacity)))
    }
}
