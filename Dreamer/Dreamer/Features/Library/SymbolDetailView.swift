import SwiftUI

/// Symbol detail pushed from the Library and Home thumbs.
struct SymbolDetailView: View {
    let symbol: LibrarySymbol
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            DS.Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    hero
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            IconCircle(glyph: symbol.glyph)
                            Overline(text: "What it can mean")
                        }
                        Text(symbol.detail)
                            .textStyle(.bodyLong)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DS.Space.cardPaddingLarge)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: DS.Radius.cardLarge)
                    .padding(.horizontal, DS.Space.screen)
                    .enterUp(0.5)

                    Text("Dreamer offers reflection, not medical advice.")
                        .textStyle(.label, color: DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)

            HeaderBar(leading: {
                GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
            }, center: { EmptyView() })
            .enterUp(0.1)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                DreamImage.image(named: symbol.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .accessibilityHidden(true)
            LinearGradient(colors: [DS.Palette.background.opacity(0), DS.Palette.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
            VStack(alignment: .leading, spacing: 8) {
                Text(symbol.title)
                    .textStyle(.display)
                    .accessibilityAddTraits(.isHeader)
                Text(symbol.meaning).textStyle(.body, color: DS.Palette.textSecondary)
            }
            .padding(.horizontal, DS.Space.screen)
            .enterUp(0.3)
        }
        .frame(height: 320)
    }
}

#Preview {
    SymbolDetailView(symbol: MockData.librarySymbols[0])
}
