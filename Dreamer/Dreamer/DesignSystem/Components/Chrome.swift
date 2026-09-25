import SwiftUI

// MARK: - Tab bar

struct TabBarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

/// Floating glass capsule with a sliding white pill.
struct DreamerTabBar<Selection: Hashable>: View {
    var items: [(value: Selection, item: TabBarItem)]
    @Binding var selection: Selection

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.item.id) { entry in
                let active = entry.value == selection
                Button { selection = entry.value } label: {
                    VStack(spacing: 3) {
                        Image(systemName: entry.item.systemImage)
                            .font(.system(size: 19, weight: active ? .regular : .light))
                            .foregroundStyle(active ? DS.Palette.accent : DS.Palette.tabInactive)
                        Text(entry.item.title)
                            .font(DreamerFont.fixed(11, .medium))
                            .foregroundStyle(active ? DS.Palette.textPrimary : DS.Palette.tabInactive)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(DS.Palette.surface.opacity(0.95))
                                .shadow(color: DS.Palette.shadow.opacity(0.16), radius: 8, x: 0, y: 6)
                                .matchedGeometryEffect(id: "tabPill", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.item.title)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(6)
        .frame(height: DS.Size.tabBarHeight)
        .glassCard(radius: 32, style: .tabBar)
        .padding(.horizontal, DS.Size.tabBarInset)
        .animation(.soft(0.45), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Headers

/// Header row: optional leading button, centered content, optional trailing button.
/// Sits 6 pt below the top safe area (64 pt from the top on a 390 x 844 canvas).
struct HeaderBar<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            center()
            HStack {
                leading()
                Spacer()
                trailing()
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Size.iconButton)
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.headerTop)
    }
}

extension HeaderBar where Leading == EmptyView {
    init(@ViewBuilder center: @escaping () -> Center, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(leading: { EmptyView() }, center: center, trailing: trailing)
    }
}

extension HeaderBar where Trailing == EmptyView {
    init(@ViewBuilder leading: @escaping () -> Leading, @ViewBuilder center: @escaping () -> Center) {
        self.init(leading: leading, center: center, trailing: { EmptyView() })
    }
}

/// White `title` over the sky (Journal, Library, Settings).
struct SkyTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .textStyle(.title, color: DS.Palette.white)
            .skyTextShadow()
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Bottom sheet

/// Custom sheet: translucent near-white fill, top radius 32, grabber, soft upward shadow.
struct BottomSheetContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DS.Palette.line.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            content()
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous)
                .fill(DS.Palette.sheetFill.opacity(0.92))
                .background(.ultraThinMaterial,
                            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
                .shadow(color: DS.Palette.sheetShadow.opacity(0.2), radius: 20, x: 0, y: -12)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Navigation helpers

extension View {
    /// Every screen draws its own header; the system bar stays hidden.
    func hideSystemNavigationBar() -> some View {
        toolbar(.hidden, for: .navigationBar)
    }
}
