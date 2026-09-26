import SwiftUI

// MARK: - Page dots

/// Active dot = 26 pt capsule, others 8 pt at 25 %. `position` is continuous, so while a pager is
/// dragged the active capsule flows from one dot to the next.
struct PageDots: View {
    var count = 3
    var position: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                let activity = max(0, 1 - abs(position - CGFloat(i)))
                Capsule()
                    .fill(DS.Palette.accent.opacity(0.25 + 0.75 * activity))
                    .frame(width: 8 + 18 * activity, height: 8)
            }
        }
        // Decoration: an 8 pt row is no touch target, and VoiceOver moves through the pages by
        // their titles and buttons.
        .accessibilityHidden(true)
    }
}

extension PageDots {
    init(count: Int = 3, index: Int) {
        self.init(count: count, position: CGFloat(index))
    }
}

// MARK: - Progress capsule

/// 6 pt progress track. Grows from 0 on appear and animates between values.
struct ProgressCapsule: View {
    var value: Double   // 0...1
    var initialValue: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.entranceActive) private var entranceActive
    @State private var shown: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.track)
                Capsule().fill(DS.Palette.cta)
                    .frame(width: geo.size.width * (shown ?? initialValue))
            }
        }
        .frame(height: 6)
        .onAppear { if entranceActive { grow() } }
        .onChange(of: entranceActive) { _, active in if active { grow() } }
        .onChange(of: value) { _, newValue in
            withAnimation(reduceMotion ? nil : .soft(1)) { shown = newValue }
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }

    private func grow() {
        guard shown == nil else { return }
        guard !reduceMotion else { shown = value; return }
        withAnimation(.soft(1).delay(0.3)) { shown = value }
    }
}

// MARK: - Ring

/// Circular progress ring (Journal summary). Trims from 0 to value on appear, ~1.4 s.
struct ProgressRing<Label: View>: View {
    var value: Double
    var lineWidth: CGFloat = 5
    @ViewBuilder var label: () -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(DS.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(DS.Palette.iconSoft, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .onAppear {
            guard !reduceMotion else { shown = value; return }
            withAnimation(.easeOut(duration: 1.4).delay(0.3)) { shown = value }
        }
        .onChange(of: value) { _, newValue in shown = newValue }
    }
}

// MARK: - Week strip

struct WeekDayState: Identifiable, Hashable {
    let id: Int
    let letter: String
    let isDone: Bool
    var accessibilityName: String
}

/// 7 circles: empty ring or white filled with a check that pops in one after another.
struct WeekStrip: View {
    var days: [WeekDayState]
    /// Delay before the first check pops (docs: 1.14 s on Home).
    var popDelay: Double = 1.14

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { offset, day in
                VStack(spacing: 8) {
                    WeekDayCircle(isDone: day.isDone, delay: popDelay + Double(doneIndex(before: offset)) * 0.12)
                    Text(day.letter).textStyle(.small, color: DS.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.accessibilityName), \(day.isDone ? "dream caught" : "no dream")")
            }
        }
    }

    private func doneIndex(before offset: Int) -> Int {
        days.prefix(offset).filter(\.isDone).count
    }
}

private struct WeekDayCircle: View {
    var isDone: Bool
    var delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        ZStack {
            Circle().strokeBorder(DS.Palette.weekRing.opacity(0.45), lineWidth: 1.5)
                .opacity(isDone ? 0 : 1)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.Palette.icon)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(DS.Palette.surface))
                    .shadow(color: DS.Palette.shadow.opacity(0.18), radius: 7, x: 0, y: 4)
                    .scaleEffect(popped ? 1 : 0.4)
                    .opacity(popped ? 1 : 0)
            }
        }
        .frame(width: 38, height: 38)
        .onAppear {
            guard !reduceMotion else { popped = true; return }
            withAnimation(.pop.delay(delay)) { popped = true }
        }
    }
}

// MARK: - Waveform

/// Row of bars that animate scaleY 0.25 <-> 1 with a per-bar rhythm. Frozen when not animating.
struct WaveformBars: View {
    var count = 24
    var barWidth: CGFloat = 3
    var height: CGFloat = 26
    var spacing: CGFloat = 5
    var color: Color = DS.Palette.iconSoft
    var isAnimating = true
    /// Live input levels (0...1, newest last). When set, bars follow the voice instead of the loop.
    var levels: [CGFloat]? = nil

    /// Relative resting heights, so the frozen state still reads as a waveform.
    private static let pattern: [Double] = [0.35, 0.7, 0.5, 0.9, 0.4, 1, 0.6, 0.3, 0.75, 0.5, 0.95, 0.45,
                                            0.65, 0.3, 0.85, 0.55, 1, 0.4, 0.7, 0.35, 0.8, 0.5, 0.6, 0.9]

    var body: some View {
        Group {
            if let levels {
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: barWidth, height: height * voiceScale(i, levels: levels))
                            .frame(height: height)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: levels)
            } else {
                LoopingView(isPaused: !isAnimating) { time in
                    HStack(spacing: spacing) {
                        ForEach(0..<count, id: \.self) { i in
                            Capsule()
                                .fill(color)
                                .frame(width: barWidth, height: height * scale(for: i, time: time))
                                .frame(height: height)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Mirrored around the centre bar so speech ripples outwards; silence keeps a low line.
    private func voiceScale(_ i: Int, levels: [CGFloat]) -> CGFloat {
        guard !levels.isEmpty else { return 0.25 }
        let distance = abs(i - count / 2)
        let level = levels[max(0, levels.count - 1 - distance)]
        let texture = 0.7 + 0.3 * Self.pattern[i % Self.pattern.count]
        return 0.25 + 0.75 * min(1, level * texture)
    }

    private func scale(for i: Int, time: TimeInterval) -> CGFloat {
        let base = Self.pattern[i % Self.pattern.count]
        guard time != 0 else { return base }
        let period = 1.4 + Double(i % 6) * 0.2          // 0.7-1.2 s each way
        let wave = Loop.wave(time, period: period, delay: Double(i) * 0.05)
        return 0.25 + 0.75 * (base * 0.4 + wave * 0.6)
    }
}

// MARK: - Recording dot

struct PulsingDot: View {
    var color: Color = DS.Palette.recordDot
    var size: CGFloat = 8

    var body: some View {
        LoopingView { time in
            let t = Loop.wave(time, period: 1.2)
            Circle().fill(color)
                .frame(width: size, height: size)
                .scaleEffect(0.8 + 0.3 * t)
                .opacity(0.5 + 0.5 * t)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Blinking caret text

/// Text that grows as it is typed, followed by a caret blinking every 0.5 s.
struct CaretText: View {
    var text: String
    var style: TextStyle = .body
    var color: Color = DS.Palette.textPrimary
    var showsCaret = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 2)
            let visible = showsCaret && (reduceMotion || tick.isMultiple(of: 2))
            let caret = Text("|").foregroundStyle(visible ? DS.Palette.accent : .clear)
            Text("\(Text(verbatim: text))\(caret)")
                .textStyle(style, color: color)
        }
        .accessibilityLabel(text)
    }
}

#Preview("Indicators") {
    ZStack {
        SkyBackground(kind: .top)
        VStack(spacing: 24) {
            PageDots(index: 1)
            ProgressCapsule(value: 0.5)
            WeekStrip(days: (0..<7).map { WeekDayState(id: $0, letter: "MTWTFSS".map(String.init)[$0], isDone: [2, 3, 4].contains($0), accessibilityName: "Day") })
                .padding(16).glassCard()
            ProgressRing(value: 0.8) { Text("12").textStyle(.heading) }.frame(width: 54, height: 54)
            WaveformBars()
            CaretText(text: "I was back in my grandmother’s house")
        }
        .padding(DS.Space.screen)
    }
}
