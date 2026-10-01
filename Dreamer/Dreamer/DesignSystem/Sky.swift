import SwiftUI

// MARK: - Fades

/// The two sky fades from the design, drawn over any sky image.
struct SkyFade: View {
    enum Kind { case top, full }
    var kind: Kind

    var body: some View {
        GeometryReader { geo in
            let bg = DS.Palette.background
            switch kind {
            case .top:
                // Sky only at the top: y 150 ... 380 clear -> 60% (at 45%) -> background, solid below.
                VStack(spacing: 0) {
                    Color.clear.frame(height: DS.Size.topSkyFadeStart)
                    LinearGradient(stops: [
                        .init(color: bg.opacity(0), location: 0),
                        .init(color: DS.Palette.fadeTop.opacity(0.6), location: 0.45),
                        .init(color: bg, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: DS.Size.topSkyHeight - DS.Size.topSkyFadeStart)
                    bg
                }
            case .full:
                // y 470 ... bottom: clear -> 75% (at 35%) -> background (at 70%)
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.size.height * (470.0 / 844.0))
                    LinearGradient(stops: [
                        .init(color: bg.opacity(0), location: 0),
                        .init(color: DS.Palette.fadeFull.opacity(0.75), location: 0.35),
                        .init(color: bg, location: 0.7)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
        }
    }
}

// MARK: - Single-screen sky

/// Sky photo with a slow drift: top variant (300 pt, fades early) or full screen.
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

                SkyFade(kind: kind == .top ? .top : .full)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Plain

/// The background of screens without a picture (Journal, Library, Settings, the lock). Pictures
/// stay on the onboarding, the top of Home, the record flow and the paywall.
struct ScreenBackground: View {
    var body: some View {
        DS.Palette.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Panorama

/// One wide sky shared by a pager. It moves with parallax as the pages scroll, and the
/// "top sky" fade blends in by `topSkyAmount` (0 = full sky, 1 = sky only at the top).
struct PanoramaSkyBackground: View {
    var image: ImageResource
    /// Pager position: 0 = first page, 1 = last page.
    var progress: CGFloat
    var pageCount: Int
    var topSkyAmount: Double
    /// How far the sky travels per page, relative to the screen width (0.55 fits a 16:9 image).
    var parallax: CGFloat = 0.55

    private let drift: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let travel = size.width * parallax * CGFloat(max(pageCount - 1, 0))
            let width = size.width + travel + drift * 2
            let clamped = min(max(progress, 0), 1)

            ZStack(alignment: .topLeading) {
                DS.Palette.background
                LoopingView { time in
                    let idleDrift = (Loop.wave(time, period: 46) * 2 - 1) * drift
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: size.height)
                        .clipped()
                        .offset(x: -drift - travel * clamped + idleDrift)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()

                SkyFade(kind: .full)
                SkyFade(kind: .top).opacity(topSkyAmount)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Scroll edge effect

extension View {
    /// iOS 26 blurs content under bars pinned to a scroll view; the design wants clear sky there.
    @ViewBuilder func scrollEdgeEffectsHidden() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

#Preview("Sky") {
    TabView {
        SkyBackground(kind: .top)
        SkyBackground(kind: .full)
        PanoramaSkyBackground(image: .onboardingSky, progress: 0.5, pageCount: 6, topSkyAmount: 0.5)
    }
    .tabViewStyle(.page)
}
