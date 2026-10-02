import SwiftUI

/// White radial-gradient orb with two breathing concentric glass rings.
struct OrbView: View {
    enum Size {
        case home, onboarding, analysis, record

        var frame: CGFloat { switch self { case .home: 150; case .onboarding: 170; case .analysis: 190; case .record: 210 } }
        var orb: CGFloat { switch self { case .home: 92; case .onboarding: 98; case .analysis: 110; case .record: 122 } }
    }

    var glyph: OrbGlyph
    var size: Size = .home
    /// Recording: faster, stronger breathing.
    var isActive = false

    var body: some View {
        let period = isActive ? 1.9 : 4.4
        LoopingView { time in
            let outer = Loop.wave(time, period: period)
            let inner = Loop.wave(time, period: period, delay: 0.5)
            let float = Loop.wave(time, period: 5)
            ZStack {
                ring(fill: 0.12, stroke: 0.75)
                    .scaleEffect(1 + (isActive ? 0.18 : 0.14) * outer)
                    .opacity(0.7 - 0.5 * outer)
                ring(fill: 0.2, stroke: 0.9)
                    .padding(size.frame * 0.1)
                    .scaleEffect(1 + (isActive ? 0.12 : 0.08) * inner)
                    .opacity(0.9 - 0.45 * inner)
                orb.offset(y: -5 * float)
            }
        }
        .frame(width: size.frame, height: size.frame)
    }

    private func ring(fill: Double, stroke: Double) -> some View {
        Circle()
            .fill(Color.white.opacity(fill))
            .overlay(Circle().strokeBorder(Color.white.opacity(stroke), lineWidth: 1))
    }

    private var orb: some View {
        glyphView
            .frame(width: size.orb, height: size.orb)
            .background(Circle().fill(DS.Palette.orbGradient))
            .shadow(color: DS.Palette.orbShadow.opacity(0.22), radius: 16, x: 0, y: 14)
    }

    @ViewBuilder private var glyphView: some View {
        let glyphSize = size.orb * 0.36
        switch glyph {
        case .sparkle:
            SparkleShape()
                .stroke(DS.Palette.iconSoft, style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
                .frame(width: glyphSize, height: glyphSize)
        case .mic, .moon, .envelope:
            Image(systemName: glyph.systemName)
                .font(.system(size: glyphSize * (glyph == .envelope ? 0.9 : 1), weight: .regular))
                .foregroundStyle(DS.Palette.iconSoft)
        }
    }
}

enum OrbGlyph {
    case mic, moon, sparkle, envelope

    fileprivate var systemName: String {
        switch self {
        case .mic: "mic"
        case .moon: "moon"
        case .envelope: "envelope"
        case .sparkle: "sparkle"
        }
    }
}

/// Tappable orb (Home mic).
struct OrbButton: View {
    var glyph: OrbGlyph = .mic
    var size: OrbView.Size = .home
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button {
            // The app's main button: a firm knock, stronger than the light tap of the other
            // buttons. Played in the tap itself, before the action opens recording, so it never
            // races the recording session (which mutes haptics unless told otherwise).
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
            action()
        } label: {
            OrbView(glyph: glyph, size: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Orb") {
    ZStack {
        SkyBackground(kind: .full)
        VStack {
            OrbView(glyph: .moon, size: .onboarding)
            OrbView(glyph: .mic, size: .record, isActive: true)
        }
    }
}
