import SwiftUI

/// 13 Library (tab).
struct LibraryView: View {
    @State private var viewModel: LibraryViewModel

    private let columns = [GridItem(.flexible(), spacing: DS.Space.stack), GridItem(.flexible(), spacing: DS.Space.stack)]

    init(viewModel: LibraryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeaderBar(center: { ScreenTitle(text: "Library") }, trailing: { EmptyView() })
                    GlassSearchField(placeholder: "Search a symbol, e.g. teeth", text: $viewModel.query)
                        .padding(.horizontal, DS.Space.screen)
                        .padding(.top, 18)
                    categories
                        .padding(.top, 8)
                    SectionHeader(title: viewModel.sectionTitle)
                        .padding(.horizontal, DS.Space.screen)
                        .padding(.top, 14)
                    grid
                        .environment(\.lightweightGlass, true)
                        .padding(.horizontal, DS.Space.screen)
                        .padding(.top, 14)
                }
                .padding(.bottom, DS.Space.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        // On a new category or search only: animating every appended page made the grid jump
        // while it scrolled.
        .animation(.soft(0.4), value: viewModel.listIdentity)
        .task(id: viewModel.category) { await viewModel.refresh() }
        .trackScreen(.library)
    }

    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.categories) { category in
                    Chip(title: category.title, isOn: viewModel.category == category, size: .small) {
                        viewModel.category = category
                    }
                }
            }
            .padding(.horizontal, DS.Space.screen)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var grid: some View {
        if viewModel.symbols.isEmpty && viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
        } else if viewModel.symbols.isEmpty {
            Text("Nothing found. Try another word.")
                .textStyle(.body, color: DS.Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
        } else {
            LazyVGrid(columns: columns, spacing: DS.Space.stack) {
                ForEach(viewModel.symbols) { symbol in
                    Button { viewModel.open(symbol) } label: {
                        SymbolTile(symbol: symbol, viewModel: viewModel)
                    }
                    .buttonStyle(PressableButtonStyle())
                    // Lazy grid: the last tile appears only when scrolled near, and loads the next page.
                    .task { await viewModel.symbolAppeared(symbol) }
                }
            }
            // There for as long as pages remain, so the content does not grow and shrink by its
            // height each time one loads.
            if viewModel.canLoadMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.top, 8)
            }
        }
    }
}

/// Image on top, glass footer with title and meaning.
private struct SymbolTile: View {
    var symbol: LibrarySymbol
    var viewModel: LibraryViewModel
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (image.map(Image.init(uiImage:)) ?? DreamImage.image(named: symbol.imageName))
                .resizable()
                .scaledToFill()
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.title).textStyle(.bodyStrong).lineLimit(1)
                Text(symbol.meaning).textStyle(.label, color: DS.Palette.textTertiary).lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.option, style: .continuous))
        .glassCard(radius: DS.Radius.option)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task(id: symbol.imageURL) {
            // Tiles are about 180 pt wide.
            guard let data = await viewModel.imageData(for: symbol) else { return }
            image = await ImageDownsampler.decoded(from: data, pointSize: 200)
        }
    }
}

#Preview {
    LibraryView(viewModel: LibraryViewModel(appState: .preview(), catalog: MockSymbolCatalog()))
}
