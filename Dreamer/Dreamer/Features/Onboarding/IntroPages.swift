import SwiftUI

// MARK: - Shared layout

/// Intro page content: hero, then title and body. The top bar, the page dots and the CTA belong to
/// the flow (OnboardingPagesView), so they stay put while this changes. Scrolls on small screens
/// so nothing clips.
private struct IntroContentLayout<Top: View, Hero: View>: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var top: () -> Top
    @ViewBuilder var hero: () -> Hero

    /// The content area of an iPhone SE is about 430 pt, of a 6.1" phone about 560.
    @State private var compact = false

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                top()
                Spacer(minLength: compact ? 8 : 16)
                hero()
                Spacer(minLength: compact ? 14 : 24)
                VStack(spacing: 12) {
                    Text(title)
                        .textStyle(.display)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .enterUp(0.25)
                    Text(message)
                        .textStyle(.body, color: DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.text - DS.Space.cta)
                        .enterUp(0.35)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.cta)
        }
        .onGeometryChange(for: Bool.self) { $0.size.height < 480 } action: { compact = $0 }
        .environment(\.introCompact, compact)
    }
}

extension EnvironmentValues {
    /// The intro content area is short (iPhone SE): heroes shrink so the title and the text below
    /// them stay on screen above the page dots.
    @Entry fileprivate var introCompact = false
}

/// The intro orb, a size smaller where the content area is short. With an action it is a button
/// that moves the onboarding on, like "Continue" below it.
private struct IntroOrb: View {
    var glyph: OrbGlyph
    var topPadding: CGFloat = 0
    var action: (() -> Void)?
    @Environment(\.introCompact) private var compact

    var body: some View {
        Group {
            if let action {
                Button(action: action) { orb.contentShape(Circle()) }
                    .buttonStyle(PressableButtonStyle())
                    // VoiceOver already has "Continue" for the same step.
                    .accessibilityHidden(true)
            } else {
                orb
            }
        }
        .padding(.top, compact ? topPadding * 0.4 : topPadding)
    }

    private var orb: some View {
        OrbView(glyph: glyph, size: compact ? .home : .onboarding)
    }
}

/// A hero column whose gaps tighten where the content area is short.
private struct IntroHeroStack<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.introCompact) private var compact

    var body: some View {
        VStack(spacing: compact ? spacing * 0.6 : spacing, content: content)
    }
}

extension IntroContentLayout where Top == EmptyView {
    init(title: LocalizedStringKey, message: LocalizedStringKey, @ViewBuilder hero: @escaping () -> Hero) {
        self.init(title: title, message: message, top: { EmptyView() }, hero: hero)
    }
}

// MARK: - 01 Welcome

struct WelcomeContent: View {
    /// The orb moves on, like "Get started".
    var onContinue: () -> Void = {}

    var body: some View {
        IntroContentLayout(
            title: "Your dreams are\ntalking to you",
            message: "Tell a dream in 10 seconds after you wake up. Get a personal interpretation every morning."
        ) {
            VStack(spacing: 6) {
                Logo(large: true)
                Text("Listen to your dreams")
                    .textCase(.uppercase)
                    .font(DreamerFont.fixed(10))
                    .tracking(2)
                    .foregroundStyle(DS.Palette.white)
                    .skyTextShadow()
            }
            .enterUp(0.15)
        } hero: {
            IntroOrb(glyph: .moon, topPadding: 40, action: onContinue)
                .enterUp(0.2)
        }
    }
}

// MARK: - 02 Record

struct RecordIntroContent: View {
    /// The orb moves on, like "Continue".
    var onContinue: () -> Void = {}

    var body: some View {
        IntroContentLayout(
            title: "Catch it before it fades",
            message: "Say your dream out loud in 10 seconds. We write it down while you are still half asleep."
        ) {
            IntroHeroStack(spacing: 30) {
                IntroOrb(glyph: .mic, action: onContinue)
                    .enterUp(0.1)
                TypewriterText(text: MockData.onboardingQuote, startDelay: 0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .glassCard(radius: DS.Radius.option)
                    .padding(.horizontal, 36 - DS.Space.cta)
                    .enterUp(0.2)
            }
        }
    }
}

// MARK: - 03 Understand

struct UnderstandContent: View {
    var body: some View {
        IntroContentLayout(
            title: "Understand it. Then see it.",
            message: "A personal interpretation, the symbols behind it and an image of your dream."
        ) {
            IntroHeroStack(spacing: 18) {
                FannedImages()
                    .enterUp(0.1)
                HStack(spacing: 8) {
                    TwinklingSparkle(size: 12)
                    Text("Stairs · Roots · A voice")
                        .font(DreamerFont.fixed(12))
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(height: 32)
                .glassCapsule()
                .enterUp(0.2)
            }
            .padding(.top, 30)
        }
    }
}

/// Three dream images fanned out, each floating at its own rhythm.
private struct FannedImages: View {
    var body: some View {
        LoopingView { time in
            ZStack {
                card(.dreamThumb2, width: 130, height: 160, radius: 22)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -78, y: 18 - 5 * Loop.wave(time, period: 5.2, delay: 0.4))
                card(.dreamThumb4, width: 130, height: 160, radius: 22)
                    .rotationEffect(.degrees(8))
                    .offset(x: 78, y: 18 - 5 * Loop.wave(time, period: 5.8, delay: 0.8))
                card(.dreamThumb1, width: 140, height: 180, radius: 24)
                    .offset(y: -5 * Loop.wave(time, period: 4.6))
            }
        }
        .frame(height: 210)
        .accessibilityHidden(true)
    }

    private func card(_ image: ImageResource, width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .shadow(color: DS.Palette.shadow.opacity(0.2), radius: 14, x: 0, y: 10)
    }
}

#Preview("Welcome") {
    ZStack { SkyBackground(kind: .full); WelcomeContent() }
}

#Preview("Record intro") {
    ZStack { SkyBackground(kind: .full); RecordIntroContent() }
}

#Preview("Understand") {
    ZStack { SkyBackground(kind: .full); UnderstandContent() }
}
