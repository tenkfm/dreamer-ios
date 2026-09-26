import SwiftUI

// Motion tokens from docs/05-motion.md.

extension Animation {
    /// CSS cubic-bezier(.22,.8,.26,1): the soft ease-out used almost everywhere.
    static func soft(_ duration: Double = 0.9) -> Animation {
        .timingCurve(0.22, 0.8, 0.26, 1, duration: duration)
    }

    /// A screen replacing another like a navigation push (onboarding -> account -> paywall):
    /// critically damped, so the screens glide in without the soft curve's jump at the start.
    static let push = Animation.smooth(duration: 0.5)

    /// Button press, 0.18 s.
    static let press = Animation.timingCurve(0.3, 0.7, 0.4, 1, duration: 0.18)

    /// Toggle knob with slight overshoot (cubic-bezier .3,.7,.4,1.3).
    static let knob = Animation.spring(response: 0.35, dampingFraction: 0.62)

    /// Check "pop": scale .4 -> 1.1 -> 1, 0.55 s bouncy.
    static let pop = Animation.spring(response: 0.45, dampingFraction: 0.55)
}

// MARK: - Loops

/// Pure functions for time-driven loops. Loops are rendered with `TimelineView` instead of
/// `repeatForever` so they never leak into layout animations and can pause/freeze cleanly.
enum Loop {
    /// Smooth 0 -> 1 -> 0 ease-in-out wave with the given period, like a CSS `alternate` loop
    /// where one full cycle (there and back) lasts `period`.
    static func wave(_ time: TimeInterval, period: Double, delay: Double = 0) -> Double {
        let phase = (time - delay) / period
        return (1 - cos(phase * 2 * .pi)) / 2
    }

    /// Linear 0 ..< 1 sawtooth, used for spinners.
    static func linear(_ time: TimeInterval, period: Double) -> Double {
        let value = time.truncatingRemainder(dividingBy: period) / period
        return value < 0 ? value + 1 : value
    }
}

/// Runs a time-driven loop. With Reduce Motion (or `isPaused`) the content receives a frozen time.
struct LoopingView<Content: View>: View {
    var isPaused = false
    @ViewBuilder var content: (TimeInterval) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Off screen (another tab, a pushed screen) the timeline stops: no frames nobody sees.
    @State private var isVisible = false

    private var paused: Bool { isPaused || reduceMotion || !isVisible || scenePhase != .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { context in
            content(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

// MARK: - Entrance gating

extension EnvironmentValues {
    /// False while a view is built but not on screen yet (e.g. the next page of a pager).
    /// Entrance animations wait for it to become true, then play once.
    @Entry var entranceActive: Bool = true
    /// False on a screen that arrives with a transition of its own (a push): its elements come
    /// with it instead of rising one by one after it has landed.
    @Entry var entranceAnimated: Bool = true
}

// MARK: - Enter-up entrance

struct EnterUp: ViewModifier {
    var delay: Double
    var distance: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.entranceActive) private var entranceActive
    @Environment(\.entranceAnimated) private var entranceAnimated
    @State private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion || !entranceAnimated
        return content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : distance)
            .onAppear { if entranceActive { reveal() } }
            .onChange(of: entranceActive) { _, active in if active { reveal() } }
    }

    private func reveal() {
        guard !reduceMotion, !shown else { return }
        withAnimation(.soft().delay(delay)) { shown = true }
    }
}

extension View {
    /// Staggered entrance: opacity 0 -> 1, y +18 -> 0, 0.9 s soft ease-out.
    func enterUp(_ delay: Double = 0, distance: CGFloat = 18) -> some View {
        modifier(EnterUp(delay: delay, distance: distance))
    }
}

extension AnyTransition {
    /// Onboarding / flow step change: incoming enters up, outgoing fades and lifts.
    static var stepChange: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 18)),
            removal: .opacity.combined(with: .offset(y: -12))
        )
    }
}
