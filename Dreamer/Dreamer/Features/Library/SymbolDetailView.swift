import SwiftUI

/// Symbol detail pushed from the Library and Home thumbs.
struct SymbolDetailView: View {
    @State private var viewModel: SymbolDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SymbolDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Palette.background.ignoresSafeArea()
            if let symbol = viewModel.symbol {
                content(symbol)
            } else if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("This symbol isn’t available offline yet.")
                    .textStyle(.body, color: DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HeaderBar(leading: {
                GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
            }, center: { EmptyView() })
        }
        .task { await viewModel.appeared() }
        .trackScreen(.symbol)
    }

    private func content(_ symbol: LibrarySymbol) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.section) {
                hero(symbol)
                Group {
                    meaningCard(symbol)
                    ForEach(viewModel.lenses, id: \.lens) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Overline(text: item.lens.title)
                            Text(item.text)
                                .textStyle(.bodyLong)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DS.Space.cardPaddingLarge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: DS.Radius.cardLarge)
                    }
                    if let question = symbol.question, !question.isEmpty {
                        InsightCard(overline: "A question for you", text: question)
                    }
                    if !viewModel.related.isEmpty {
                        related
                    }
                    Text("Mooncatch offers reflection, not medical advice.")
                        .textStyle(.label, color: DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, DS.Space.screen)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
    }

    private func meaningCard(_ symbol: LibrarySymbol) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconCircle(glyph: symbol.glyph)
                Overline(text: "What it can mean")
            }
            Text(symbol.detail.isEmpty ? symbol.meaning : symbol.detail)
                .textStyle(.bodyLong)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.cardPaddingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: DS.Radius.cardLarge)
    }

    private var related: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Related symbols")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(viewModel.related) { symbol in
                    Chip(title: symbol.title, isOn: false, size: .small) { viewModel.open(symbol) }
                }
            }
        }
    }

    private func hero(_ symbol: LibrarySymbol) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                (viewModel.image.map(Image.init(uiImage:)) ?? DreamImage.image(named: nil))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .animation(.soft(0.6), value: viewModel.image)
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
        }
        .frame(height: 320)
    }
}

#Preview {
    SymbolDetailView(viewModel: SymbolDetailViewModel(slug: MockData.librarySymbols[0].id, catalog: MockSymbolCatalog(),
                                                      appState: .preview()))
}
