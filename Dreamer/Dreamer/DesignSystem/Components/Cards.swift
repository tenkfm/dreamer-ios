import SwiftUI

// MARK: - Section header

/// `heading` title with an optional trailing caption or text button ("See all", "2 more lenses").
struct SectionHeader: View {
    var title: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).textStyle(.heading).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailing).textStyle(.secondary, color: DS.Palette.textTertiary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(trailing).textStyle(.label, color: DS.Palette.textTertiary)
                }
            }
        }
    }
}

// MARK: - Overline

struct Overline: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).textStyle(.overline, color: DS.Palette.overline)
    }
}

// MARK: - Insight card

/// Glass card: twinkling peach sparkle, overline, text and an optional pill button.
struct InsightCard: View {
    var overline: String
    var text: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TwinklingSparkle(size: 18).padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Overline(text: overline)
                bodyText
                if let buttonTitle, let action {
                    // Design fix: the pill sits on its own line so the text never runs under it.
                    PillButton(title: buttonTitle, action: action)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, -12)
                        .padding(.bottom, -14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.cardPaddingLarge)
        .padding(.vertical, 18)
        .glassCard(radius: DS.Radius.cardLarge)
    }
}

private extension InsightCard {
    var bodyText: some View {
        Text(text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Dream thumb

/// 84 x 94 image with a caption that floats slowly.
struct DreamThumb: View {
    var title: String
    var image: Image
    /// Index in the row: picks one of four float rhythms so neighbours never sync.
    var index: Int

    var body: some View {
        VStack(spacing: 8) {
            LoopingView { time in
                let periods: [Double] = [4.0, 4.6, 5.2, 5.8]
                let t = Loop.wave(time, period: periods[index % 4], delay: Double(index) * 0.4)
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 94)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                    .shadow(color: DS.Palette.shadow.opacity(0.15), radius: 8, x: 0, y: 6)
                    .offset(y: -5 * t)
            }
            .frame(width: 84, height: 94)
            Text(title)
                .textStyle(.label, color: DS.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Symbol card

/// 150 wide glass tile: icon circle, title and meaning.
struct SymbolCard: View {
    var title: String
    var meaning: String
    var glyph: Glyph

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconCircle(glyph: glyph, size: 34)
            Text(title).textStyle(.bodyStrong).fixedSize(horizontal: false, vertical: true)
            Text(meaning).textStyle(.label, color: DS.Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.cardPadding)
        .frame(width: 150, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard(radius: DS.Radius.option)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dream row

struct DreamRow: View {
    var title: String
    var date: String
    var image: Image
    var emotion: (title: String, color: Color)?

    var body: some View {
        HStack(spacing: 14) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).textStyle(.bodyStrong).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(date).textStyle(.secondary, color: DS.Palette.textTertiary)
                    if let emotion {
                        EmotionTag(title: emotion.title, color: emotion.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DS.Palette.icon)
        }
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .padding(.vertical, 8)
        .glassCard(radius: DS.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Settings

/// Glass group of rows. Put a `SettingsDivider` between rows.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .glassCard(radius: DS.Radius.card)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(DS.Palette.hairline).frame(height: 1)
    }
}

/// Row inside a `SettingsGroup`: icon, title and trailing accessory.
struct SettingsRow<Accessory: View>: View {
    var systemImage: String
    var title: String
    var titleColor: Color = DS.Palette.textPrimary
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 14) {
            SettingsRowLabel(systemImage: systemImage, title: title, titleColor: titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .settingsRowFrame()
    }
}

/// Icon + title of a settings row. Also used as a `Toggle` label.
struct SettingsRowLabel: View {
    var systemImage: String
    var title: String
    var titleColor: Color = DS.Palette.textPrimary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DS.Palette.icon)
                .frame(width: 22)
            Text(title).textStyle(.body, color: titleColor)
        }
    }
}

extension View {
    /// Row insets and minimum height inside a `SettingsGroup`.
    func settingsRowFrame() -> some View {
        padding(.horizontal, 18)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
    }
}

/// Trailing "value + chevron" accessory.
struct SettingsValue: View {
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            if let value { Text(value).textStyle(.secondary, color: DS.Palette.textTertiary) }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DS.Palette.icon)
        }
    }
}

// MARK: - Fields

struct GlassSearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(DS.Palette.icon)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(DS.Palette.textTertiary.opacity(0.8)))
                .textStyle(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.tabInactive)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, text.isEmpty ? 20 : 4)
        .frame(height: 50)
        .glassCapsule()
    }
}

/// Single-line glass field with a leading icon (email on the account step).
struct GlassTextField: View {
    var systemImage: String
    var placeholder: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DS.Palette.icon)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(DS.Palette.textTertiary.opacity(0.8)))
                .textStyle(.body)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, 20)
        .frame(height: DS.Size.primaryButton)
        .glassCapsule(style: .selected)
    }
}

/// Glass multi-line editor with a placeholder.
struct GlassTextEditor: View {
    var placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 92

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .textStyle(.body, color: DS.Palette.textTertiary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .textStyle(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(radius: DS.Radius.card)
    }
}

// MARK: - Toast

struct Toast: View {
    var message: String

    var body: some View {
        Text(message)
            .textStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .glassCapsule(style: .selected)
            .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Shows a transient toast at the top while `message` is non-nil; clears it after 2 s.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                Toast(message: text)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.soft(0.4)) { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.soft(0.4), value: message.wrappedValue)
    }
}

#Preview("Cards") {
    ZStack {
        SkyBackground(kind: .top)
        ScrollView {
            VStack(spacing: 14) {
                InsightCard(overline: "Your morning insight", text: "Stairs appeared in 3 of your dreams this week.", buttonTitle: "See the pattern") {}
                HStack { DreamThumb(title: "Teeth falling out", image: Image(.dreamThumb1), index: 0); DreamThumb(title: "Falling", image: Image(.dreamThumb2), index: 1) }
                SymbolCard(title: "Staircase down", meaning: "Progress you can’t see yet", glyph: .stairs).frame(height: 150)
                DreamRow(title: "The house with endless stairs", date: "Yesterday", image: Image(.dreamThumb1), emotion: ("Anxiety", DS.Emotion.anxiety))
                SettingsGroup {
                    SettingsRow(systemImage: "bell", title: "Morning reminder") { SettingsValue(value: "On") }
                    SettingsDivider()
                    SettingsRow(systemImage: "clock", title: "Reminder time") { SettingsValue(value: "7:30 AM") }
                }
            }
            .padding(DS.Space.screen)
            .padding(.top, 60)
        }
    }
}
