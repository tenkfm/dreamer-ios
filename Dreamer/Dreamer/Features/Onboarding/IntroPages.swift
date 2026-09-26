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

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                top()
                Spacer(minLength: 16)
                hero()
                Spacer(minLength: 24)
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
    }
}

extension IntroContentLayout where Top == EmptyView {
    init(title: LocalizedStringKey, message: LocalizedStringKey, @ViewBuilder hero: @escaping () -> Hero) {
        self.init(title: title, message: message, top: { EmptyView() }, hero: hero)
    }
}

// MARK: - 01 Welcome

struct WelcomeContent: View {
    var body: some View {
        IntroContentLayout(
            title: "Your dreams are\ntalking to you",
            message: "Tell a dream in 10 seconds after you wake up. Get a personal interpretation every morning."
        ) {
            VStack(spacing: 6) {
                Logo(large: true)
                Text("YOUR DREAM JOURNAL")
                    .font(DreamerFont.fixed(12))
                    .tracking(2.4)
                    .foregroundStyle(DS.Palette.white)
                    .skyTextShadow()
            }
            .enterUp(0.15)
        } hero: {
            OrbView(glyph: .moon, size: .onboarding)
                .padding(.top, 40)
                .enterUp(0.2)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 02 Record

struct RecordIntroContent: View {
    var body: some View {
        IntroContentLayout(
            title: "Catch it before it fades",
            message: "Say your dream out loud in 10 seconds. We write it down while you are still half asleep."
        ) {
            VStack(spacing: 30) {
                OrbView(glyph: .mic, size: .onboarding)
                    .enterUp(0.1)
                    .accessibilityHidden(true)
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
            VStack(spacing: 18) {
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
