import SwiftUI

// Starter implementations of the core components (docs/02 section 7).
// Extend, don't fork: every feature view should be built from these.

// MARK: - Press style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.timingCurve(0.3, 0.7, 0.4, 1, duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    if let systemImage { Image(systemName: systemImage).font(.system(size: 17, weight: .regular)) }
                    Text(title).font(TextStyle.button.font)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.primaryButton)
            .background(Capsule().fill(DS.Palette.cta))
            .shadow(color: DS.Palette.ctaShadow.opacity(0.3), radius: 15, x: 0, y: 14)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isLoading)
    }
}

struct TextLinkButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).textStyle(.link).frame(maxWidth: .infinity).frame(height: DS.Size.linkButton)
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).textStyle(.label)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(.white))
                .shadow(color: DS.Palette.shadow.opacity(0.15), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct GlassIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(DS.Palette.icon)
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .glassCircle()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Logo

struct Logo: View {
    var large = false
    var body: some View {
        Text("Dreamer")
            .font(large ? TextStyle.logoLarge.font : TextStyle.logo.font)
            .foregroundStyle(.white)
            .shadow(color: DS.Palette.skyTextShadow.opacity(0.35), radius: 7, x: 0, y: 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Orb

struct OrbButton: View {
    var systemImage: String = "mic"
    var frame: CGFloat = 150
    var orb: CGFloat = 92
    var fast = false
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var float = false

    var body: some View {
        let period = fast ? 1.9 : 4.4
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1))
                .scaleEffect(breathe ? 1.14 : 1)
                .opacity(breathe ? 0.2 : 0.7)
            Circle()
                .fill(Color.white.opacity(0.2))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .padding(frame * 0.1)
                .scaleEffect(breathe ? 1.08 : 1)
                .opacity(breathe ? 0.45 : 0.9)
                .animation(reduceMotion ? nil : .easeInOut(duration: period).repeatForever().delay(0.5), value: breathe)
            orbBody
                .offset(y: float ? -5 : 0)
        }
        .frame(width: frame, height: frame)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: period).repeatForever()) { breathe = true }
            withAnimation(.easeInOut(duration: 2.5).repeatForever()) { float = true }
        }
    }

    @ViewBuilder private var orbBody: some View {
        let glyph = Image(systemName: systemImage)
            .font(.system(size: orb * 0.38, weight: .regular))
            .foregroundStyle(DS.Palette.iconSoft)
            .frame(width: orb, height: orb)
            .background(Circle().fill(DS.Palette.orbGradient))
            .shadow(color: Color(hex: 0x4669AA).opacity(0.22), radius: 16, x: 0, y: 14)
        if let action {
            Button(action: action) { glyph }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Record last night’s dream")
        } else {
            glyph.accessibilityHidden(true)
        }
    }
}

// MARK: - Page dots / progress

struct PageDots: View {
    var count = 3
    var index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(DS.Palette.accent.opacity(i == index ? 1 : 0.25))
                    .frame(width: i == index ? 26 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

struct ProgressCapsule: View {
    var value: Double   // 0...1
    @State private var shown = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.55))
                Capsule().fill(DS.Palette.cta).frame(width: geo.size.width * (shown ? value : 0))
            }
        }
        .frame(height: 6)
        .onAppear { withAnimation(.timingCurve(0.22, 0.8, 0.26, 1, duration: 1).delay(0.3)) { shown = true } }
    }
}

// MARK: - Radio option card

struct RadioOptionCard<Leading: View>: View {
    var title: String
    var subtitle: String? = nil
    var isSelected: Bool
    @ViewBuilder var leading: () -> Leading
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textStyle(.bodyStrong)
                    if let subtitle { Text(subtitle).textStyle(.secondary, color: DS.Palette.textTertiary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .strokeBorder(isSelected ? DS.Palette.cta : DS.Palette.line.opacity(0.45),
                                  lineWidth: isSelected ? 7 : 1.5)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard(radius: DS.Radius.option, style: isSelected ? .selected : .option)
            .animation(.easeOut(duration: 0.3), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension RadioOptionCard where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected, leading: { EmptyView() }, action: action)
    }
}

/// 38 pt soft circle with an icon, used as RadioOptionCard leading content.
struct IconCircle: View {
    var systemImage: String
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .light))
            .foregroundStyle(DS.Palette.icon)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.6)))
    }
}

// MARK: - Chips

struct Chip: View {
    var title: String
    var isOn: Bool
    var onColor: Color
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).textStyle(.link)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(isOn ? onColor : Color.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(isOn ? onColor : DS.Palette.line.opacity(0.25), lineWidth: 1))
                .animation(.easeOut(duration: 0.3), value: isOn)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Small non-interactive emotion tag (11-12 pt).
struct EmotionTag: View {
    var title: String
    var color: Color
    var body: some View {
        Text(title).textStyle(.small)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(color))
    }
}

// MARK: - Segmented control

struct DreamerSegmented: View {
    var options: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(options[i])
                        .textStyle(.link, color: selection == i ? DS.Palette.textPrimary : DS.Palette.segmentInactive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == i {
                                Capsule().fill(.white)
                                    .shadow(color: DS.Palette.shadow.opacity(0.15), radius: 6, x: 0, y: 4)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCapsule()
        .animation(.timingCurve(0.22, 0.8, 0.26, 1, duration: 0.45), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Toggle

struct DreamerToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Button { configuration.isOn.toggle() } label: {
                Capsule()
                    .fill(configuration.isOn ? DS.Palette.cta : DS.Palette.line.opacity(0.3))
                    .frame(width: 50, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                            .padding(3)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: configuration.isOn)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: configuration.isOn)
        }
    }
}

// MARK: - Sparkle

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

struct TwinklingSparkle: View {
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        SparkleShape().fill(DS.Palette.peach)
            .frame(width: size, height: size)
            .scaleEffect(on ? 1.1 : 0.85)
            .rotationEffect(.degrees(on ? 20 : 0))
            .opacity(on ? 1 : 0.55)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever()) { on = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Enter-up entrance

struct EnterUp: ViewModifier {
    var delay: Double
    var distance: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.timingCurve(0.22, 0.8, 0.26, 1, duration: 0.9).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func enterUp(_ delay: Double = 0, distance: CGFloat = 18) -> some View {
        modifier(EnterUp(delay: delay, distance: distance))
    }
}

// MARK: - Tab bar

enum MainTab: String, CaseIterable, Hashable {
    case today, journal, library
    var title: String { switch self { case .today: "Today"; case .journal: "Journal"; case .library: "Library" } }
    var systemImage: String { switch self { case .today: "house"; case .journal: "book.closed"; case .library: "square.grid.2x2" } }
}

struct DreamerTabBar: View {
    @Binding var selection: MainTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let active = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(active ? DS.Palette.accent : DS.Palette.tabInactive)
                        Text(tab.title)
                            .font(DreamerFont.ui(11, .medium))
                            .foregroundStyle(active ? DS.Palette.textPrimary : DS.Palette.tabInactive)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.white.opacity(0.95))
                                .shadow(color: DS.Palette.shadow.opacity(0.16), radius: 8, x: 0, y: 6)
                                .matchedGeometryEffect(id: "tabPill", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(6)
        .frame(height: DS.Size.tabBarHeight)
        .glassCard(radius: 32, style: .tabBar)
        .padding(.horizontal, DS.Size.tabBarInset)
        .animation(.timingCurve(0.22, 0.8, 0.26, 1, duration: 0.45), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Previews

#Preview("Components") {
    ZStack {
        SkyBackground(kind: .top)
        ScrollView {
            VStack(spacing: 16) {
                Logo()
                OrbButton(action: {})
                Text("Good morning, Anna").textStyle(.title)
                RadioOptionCard(title: "Psychology", subtitle: "What your mind is working through", isSelected: true) {}
                RadioOptionCard(title: "Spiritual", subtitle: "Signs, symbols and inner guidance", isSelected: false) {}
                DreamerSegmented(options: ["Never", "Sometimes", "Often"], selection: .constant(1))
                Toggle(isOn: .constant(true)) { Text("Someone specific was in it").textStyle(.body) }
                    .toggleStyle(DreamerToggleStyle())
                    .padding(16).glassCard()
                HStack { Chip(title: "Anxiety", isOn: true, onColor: DS.Emotion.anxiety) {}; Chip(title: "Calm", isOn: false, onColor: DS.Emotion.calm) {} }
                PageDots(index: 1)
                PrimaryButton(title: "Continue") {}
                DreamerTabBar(selection: .constant(.today))
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.top, 60)
        }
    }
}
