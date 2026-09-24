import SwiftUI

/// Read-out player: play/pause circle, waveform over a progress bar, and a duration / status label.
struct VoicePlayer: View {
    enum State: Equatable { case idle, playing, paused }

    var state: State
    var progress: Double
    var durationText: String
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            playButton
            VStack(spacing: 6) {
                WaveformBars(count: 24, barWidth: 3, height: 26, spacing: 4.5, isAnimating: state == .playing)
                    .opacity(state == .playing ? 1 : 0.55)
                    .frame(maxWidth: .infinity)
                    .clipped()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.iconSoft.opacity(0.25))
                        Capsule().fill(DS.Palette.cta)
                            .frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 3)
                .animation(.linear(duration: 0.25), value: progress)
            }
            HStack(spacing: 6) {
                Image(systemName: "headphones")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(statusText)
                    .font(DreamerFont.fixed(12))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.opacity)
            }
            .frame(minWidth: 52, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .softFill(Capsule(), opacity: 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listen to your interpretation")
        .accessibilityValue(statusText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: state == .playing ? "Pause" : "Play", onToggle)
    }

    private var statusText: String {
        switch state {
        case .idle: durationText
        case .playing: "Playing"
        case .paused: "Paused"
        }
    }

    private var playButton: some View {
        Button(action: onToggle) {
            ZStack {
                if state == .playing {
                    LoopingView { time in
                        let t = Loop.wave(time, period: 1.6)
                        Circle()
                            .stroke(DS.Palette.cta.opacity(0.35 * (1 - t)), lineWidth: 2)
                            .scaleEffect(1 + 0.25 * t)
                    }
                }
                Circle().fill(DS.Palette.cta)
                    .shadow(color: DS.Palette.ctaShadow.opacity(0.3), radius: 8, x: 0, y: 6)
                Image(systemName: state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DS.Palette.white)
                    .offset(x: state == .playing ? 0 : 1.5)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: state)
    }
}

#Preview("Voice player") {
    VStack(spacing: 16) {
        VoicePlayer(state: .idle, progress: 0, durationText: "1:12") {}
        VoicePlayer(state: .playing, progress: 0.4, durationText: "1:12") {}
        VoicePlayer(state: .paused, progress: 0.6, durationText: "1:12") {}
    }
    .padding(DS.Space.screen)
    .background(DS.Palette.background)
}
