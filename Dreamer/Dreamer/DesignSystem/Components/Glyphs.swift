import SwiftUI

// MARK: - Custom shapes

/// 4-point star used as the peach sparkle glyph.
struct SparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        // Matches the SVG path M12 2 l1.9 7.1 L21 12 l-7.1 1.9 L12 21 l-1.9-7.1 L3 12 l7.1-2.9z on a 24 grid.
        let s = min(r.width, r.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var path = Path()
        path.move(to: p(12, 2))
        path.addLine(to: p(13.9, 9.1))
        path.addLine(to: p(21, 12))
        path.addLine(to: p(13.9, 13.9))
        path.addLine(to: p(12, 21))
        path.addLine(to: p(10.1, 13.9))
        path.addLine(to: p(3, 12))
        path.addLine(to: p(10.1, 9.1))
        path.closeSubpath()
        return path
    }
}

/// Small staircase going down, drawn on a 24 grid (no SF Symbol matches the design).
struct StairsShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var path = Path()
        path.move(to: p(4, 19))
        path.addLine(to: p(8.5, 19))
        path.addLine(to: p(8.5, 14.5))
        path.addLine(to: p(13, 14.5))
        path.addLine(to: p(13, 10))
        path.addLine(to: p(17.5, 10))
        path.addLine(to: p(17.5, 5.5))
        path.addLine(to: p(20, 5.5))
        return path
    }
}

// MARK: - Glyph rendering

/// Renders a model `Glyph` as a thin stroke icon matching the 24-grid design icons.
struct GlyphView: View {
    var glyph: Glyph
    var size: CGFloat = 18
    var color: Color = DS.Palette.icon

    var body: some View {
        Group {
            switch glyph {
            case .sparkle:
                SparkleShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .frame(width: size, height: size)
            case .stairs:
                StairsShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            default:
                Image(systemName: glyph.systemName)
                    .font(.system(size: size * 0.9, weight: .light))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension Glyph {
    var systemName: String {
        switch self {
        case .sparkle: "sparkle"
        case .stairs: "stairs"
        case .heart: "heart"
        case .moon: "moon"
        case .house: "house"
        case .person: "person"
        case .water: "water.waves"
        case .bird: "bird"
        case .leaf: "leaf"
        case .eye: "eye"
        }
    }
}

/// 38 pt soft circle with a glyph, used as RadioOptionCard leading content and in symbol cards.
struct IconCircle: View {
    var glyph: Glyph
    var size: CGFloat = 38

    var body: some View {
        GlyphView(glyph: glyph, size: size * 0.47)
            .frame(width: size, height: size)
            .softFill(Circle(), opacity: 0.6)
    }
}

// MARK: - Sparkle

struct TwinklingSparkle: View {
    var size: CGFloat = 20
    var color: Color = DS.Palette.peach

    var body: some View {
        LoopingView { time in
            // Scale .85 -> 1.1, rotate 0 -> 20 deg, opacity .55 -> 1, 3 s loop.
            let t = Loop.wave(time, period: 3)
            SparkleShape().fill(color)
                .frame(width: size, height: size)
                .scaleEffect(0.85 + 0.25 * t)
                .rotationEffect(.degrees(20 * t))
                .opacity(0.55 + 0.45 * t)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Glyphs") {
    HStack(spacing: 12) {
        ForEach(Glyph.allCases, id: \.self) { IconCircle(glyph: $0) }
    }
    .padding()
    .background(DS.Palette.background)
}
