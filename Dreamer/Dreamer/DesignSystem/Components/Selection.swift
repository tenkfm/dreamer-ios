import SwiftUI

// MARK: - Radio

struct RadioIndicator: View {
    var isSelected: Bool

    var body: some View {
        Circle()
            .strokeBorder(isSelected ? DS.Palette.cta : DS.Palette.line.opacity(0.45),
                          lineWidth: isSelected ? 7 : 1.5)
            .frame(width: 22, height: 22)
            .animation(.easeOut(duration: 0.3), value: isSelected)
    }
}

/// Glass option card with an optional leading view, title, description and a radio.
struct RadioOptionCard<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var isSelected: Bool
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textStyle(.bodyStrong)
                    if let subtitle {
                        Text(subtitle).textStyle(.secondary, color: DS.Palette.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                trailing()
                RadioIndicator(isSelected: isSelected)
            }
            .padding(.horizontal, DS.Space.cardPadding)
            .padding(.vertical, 14)
            .frame(minHeight: 68)
            .glassCard(radius: DS.Radius.option, style: isSelected ? .selected : .option)
            .animation(.easeOut(duration: 0.3), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension RadioOptionCard where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected,
                  leading: { EmptyView() }, trailing: { EmptyView() }, action: action)
    }
}

extension RadioOptionCard where Leading == IconCircle, Trailing == EmptyView {
    init(title: String, glyph: Glyph, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: title, isSelected: isSelected,
                  leading: { IconCircle(glyph: glyph) }, trailing: { EmptyView() }, action: action)
    }
}

/// Paywall plan: radio card with a peach badge and a price on the right.
struct PlanCard: View {
    var title: String
    var subtitle: String
    var price: String
    var badge: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RadioIndicator(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).textStyle(.bodyStrong)
                        if let badge {
                            Text(badge)
                                .font(DreamerFont.fixed(11, .medium))
                                .foregroundStyle(DS.Palette.textPrimary)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(DS.Palette.peach))
                        }
                    }
                    Text(subtitle).textStyle(.secondary, color: DS.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(price).textStyle(.bodyStrong)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassCard(radius: DS.Radius.option, style: isSelected ? .selected : .option)
            .animation(.easeOut(duration: 0.3), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Chips

struct Chip: View {
    enum Size { case regular, small }

    var title: String
    var isOn: Bool
    var onColor: Color = DS.Palette.white
    var size: Size = .regular
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(size == .regular ? .link : .label)
                .padding(.horizontal, size == .regular ? 16 : 14)
                .frame(height: size == .regular ? 38 : 34)
                .background(Capsule().fill(isOn ? onColor : Color.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(isOn ? onColor : DS.Palette.line.opacity(0.25), lineWidth: 1))
                .shadow(color: DS.Palette.shadow.opacity(isOn && onColor == DS.Palette.white ? 0.12 : 0), radius: 6, y: 3)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.3), value: isOn)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Small non-interactive emotion tag (11-12 pt).
struct EmotionTag: View {
    enum Size { case small, medium }

    var title: String
    var color: Color
    var size: Size = .small

    var body: some View {
        Text(title)
            .font(DreamerFont.fixed(size == .small ? 12 : 13))
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, size == .small ? 10 : 10)
            .frame(height: size == .small ? 22 : 26)
            .background(Capsule().fill(color))
    }
}

// MARK: - Flow layout

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Segmented control

struct DreamerSegmented<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .textStyle(.link, color: isSelected ? DS.Palette.textPrimary : DS.Palette.segmentInactive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule().fill(DS.Palette.white)
                                    .shadow(color: DS.Palette.shadow.opacity(0.15), radius: 6, x: 0, y: 4)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassCapsule()
        .animation(.soft(0.45), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Toggle

struct DreamerToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? DS.Palette.cta : DS.Palette.line.opacity(0.3))
                .frame(width: 50, height: 30)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(DS.Palette.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: DS.Palette.shadow.opacity(0.3), radius: 3, x: 0, y: 2)
                        .padding(3)
                }
                .animation(.knob, value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == DreamerToggleStyle {
    static var dreamer: DreamerToggleStyle { DreamerToggleStyle() }
}

#Preview("Selection") {
    @Previewable @State var recurrence = 1
    @Previewable @State var toggle = true
    ZStack {
        SkyBackground(kind: .top)
        ScrollView {
            VStack(spacing: 12) {
                RadioOptionCard(title: "Understand my dreams", glyph: .sparkle, isSelected: true) {}
                RadioOptionCard(title: "Spiritual", subtitle: "Signs, symbols and inner guidance", isSelected: false) {}
                PlanCard(title: "Yearly", subtitle: "$3.33 a month, billed yearly", price: "$39.99", badge: "7 days free", isSelected: true) {}
                FlowLayout {
                    Chip(title: "Fear", isOn: false, onColor: DS.Emotion.fear) {}
                    Chip(title: "Anxiety", isOn: true, onColor: DS.Emotion.anxiety) {}
                    Chip(title: "Confusion", isOn: true, onColor: DS.Emotion.confusion) {}
                    Chip(title: "Calm", isOn: false, onColor: DS.Emotion.calm) {}
                }
                DreamerSegmented(options: [0, 1, 2], selection: $recurrence) { ["Never", "Sometimes", "Often"][$0] }
                Toggle("Someone specific was in it", isOn: $toggle).toggleStyle(.dreamer).padding(16).glassCard()
                EmotionTag(title: "Anxiety", color: DS.Emotion.anxiety)
            }
            .padding(DS.Space.screen)
            .padding(.top, 80)
        }
    }
}
