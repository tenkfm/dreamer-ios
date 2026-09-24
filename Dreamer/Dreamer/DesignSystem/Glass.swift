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

// MARK: - Sky backgrounds

struct SkyBackground: View {
    enum Kind { case top, full }
    var kind: Kind

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                DS.Palette.background

                let height = kind == .top ? DS.Size.topSkyHeight : geo.size.height
                LoopingView { time in
                    // Scaled 1.12, x drifts -10 -> +10 -> -10 over 40 s (top) / 46 s (full).
                    let drift = Loop.wave(time, period: kind == .top ? 40 : 46) * 20 - 10
                    Image(kind == .top ? .skyTop : .skyTall)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: height)
                        .scaleEffect(1.12)
                        .offset(x: drift)
                }
                .frame(width: geo.size.width, height: height, alignment: .top)
                .clipped()

                fade(in: geo.size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func fade(in size: CGSize) -> some View {
        let bg = DS.Palette.background
        switch kind {
        case .top:
            // y 150 ... 380: clear -> 60% (at 45%) -> background
            VStack(spacing: 0) {
                Color.clear.frame(height: 150)
                LinearGradient(stops: [
                    .init(color: bg.opacity(0), location: 0),
                    .init(color: DS.Palette.fadeTop.opacity(0.6), location: 0.45),
                    .init(color: bg, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 230)
                Spacer(minLength: 0)
            }
        case .full:
            // y 470 ... bottom: clear -> 75% (at 35%) -> background (at 70%)
            VStack(spacing: 0) {
                Color.clear.frame(height: size.height * (470.0 / 844.0))
                LinearGradient(stops: [
                    .init(color: bg.opacity(0), location: 0),
                    .init(color: DS.Palette.fadeFull.opacity(0.75), location: 0.35),
                    .init(color: bg, location: 0.7)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

#Preview("Sky") {
    TabView {
        SkyBackground(kind: .top)
        SkyBackground(kind: .full)
    }
    .tabViewStyle(.page)
}
