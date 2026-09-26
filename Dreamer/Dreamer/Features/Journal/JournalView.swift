import SwiftUI

/// 12 Journal (tab).
struct JournalView: View {
    @State private var viewModel: JournalViewModel
    @FocusState private var searchFocused: Bool

    init(viewModel: JournalViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.enterUp(0.1)
                    if viewModel.isSearching {
                        GlassSearchField(placeholder: "Search your dreams", text: $viewModel.query)
                            .focused($searchFocused)
                            .padding(.top, 18)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                    } else {
                        JournalSummaryCard(summary: viewModel.summary)
                            .padding(.top, 18)
                            .enterUp(0.3)
                    }
                    list
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.bottom, DS.Space.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await viewModel.refresh() }
        }
        .animation(.soft(0.4), value: viewModel.isSearching)
        .task { await viewModel.refresh() }
        .toast($viewModel.toastMessage)
        .confirmationDialog("Delete this dream?", isPresented: isConfirmingDelete, titleVisibility: .visible,
                            presenting: viewModel.deleteCandidate) { _ in
            Button("Delete dream", role: .destructive) { Task { await viewModel.confirmDelete() } }
            Button("Cancel", role: .cancel) { viewModel.deleteCandidate = nil }
        } message: { _ in
            Text("It will be removed from your journal on all your devices. This can’t be undone.")
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { viewModel.deleteCandidate != nil },
                set: { if !$0 { viewModel.deleteCandidate = nil } })
    }

    private var header: some View {
        HeaderBar {
            SkyTitle(text: "Journal")
        } trailing: {
            GlassIconButton(systemImage: viewModel.isSearching ? "xmark" : "magnifyingglass",
                            accessibilityLabel: viewModel.isSearching ? "Close search" : "Search") {
                viewModel.toggleSearch()
                searchFocused = viewModel.isSearching
            }
        }
        .padding(.horizontal, -DS.Space.screen)
    }

    @ViewBuilder private var list: some View {
        if viewModel.isEmpty {
            Text(viewModel.isSearching ? "No dreams match your search." : "Your dreams will appear here.")
                .textStyle(.body, color: DS.Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
        ForEach(Array(viewModel.sections.enumerated()), id: \.element.id) { index, section in
            self.section(title: section.title, rows: section.rows, delay: 0.45 + Double(min(index, 2)) * 0.15)
        }
        if viewModel.canLoadMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    private func section(title: String, rows: [JournalViewModel.Row], delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title)
            VStack(spacing: DS.Space.stack) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { viewModel.open(row) } label: {
                        JournalRow(row: row, viewModel: viewModel)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .contextMenu {
                        Button("Delete dream", systemImage: "trash", role: .destructive) { viewModel.askToDelete(row) }
                    }
                    .task { await viewModel.rowAppeared(row) }
                    .enterUp(delay + Double(min(index, 5)) * 0.1)
                }
            }
        }
        .padding(.top, 30)
    }
}

/// A dream in the list: its thumbnail from the backend (cached), the asset in mock mode, the
/// sky while it loads or when the dream has no image yet.
private struct JournalRow: View {
    var row: JournalViewModel.Row
    var viewModel: JournalViewModel
    @State private var thumbnail: UIImage?

    var body: some View {
        DreamRow(title: row.title,
                 date: row.dateText,
                 image: thumbnail.map(Image.init(uiImage:)) ?? DreamImage.image(named: row.assetName),
                 emotion: row.emotion.map { ($0.title, $0.color) })
            .task(id: row.thumbnailURL) { thumbnail = await viewModel.thumbnail(for: row) }
    }
}

/// Month summary: count ring, most frequent symbol, emotion distribution bar and legend.
private struct JournalSummaryCard: View {
    var summary: JournalViewModel.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title).textStyle(.bodyStrong)
                    if let symbol = summary.mostFrequentSymbol {
                        Text("Most frequent symbol: \(symbol)").textStyle(.secondary, color: DS.Palette.textTertiary)
                    }
                }
                Spacer(minLength: 12)
                ProgressRing(value: summary.ringProgress, lineWidth: 4) {
                    VStack(spacing: 0) {
                        Text("\(summary.dreamCount)").font(DreamerFont.fixed(15, .medium))
                        Text(summary.dreamCount == 1 ? "dream" : "dreams").font(DreamerFont.fixed(10))
                    }
                    .foregroundStyle(DS.Palette.textPrimary)
                }
                .frame(width: 54, height: 54)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(summary.dreamCount) dreams this month")
            }
            if !summary.distribution.isEmpty {
                DistributionBar(shares: summary.distribution)
                FlowLayout(spacing: 14, lineSpacing: 6) {
                    ForEach(summary.distribution) { share in
                        HStack(spacing: 6) {
                            Circle().fill(share.emotion.color).frame(width: 8, height: 8)
                            Text(share.emotion.title).textStyle(.label, color: DS.Palette.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.Space.cardPaddingLarge)
        .padding(.vertical, 20)
        .glassCard(radius: DS.Radius.cardLarge)
    }
}

private struct DistributionBar: View {
    var shares: [JournalViewModel.EmotionShare]

    var body: some View {
        GeometryReader { geo in
            let total = max(shares.map(\.count).reduce(0, +), 1)
            let spacing: CGFloat = 4
            let available = geo.size.width - spacing * CGFloat(shares.count - 1)
            HStack(spacing: spacing) {
                ForEach(shares) { share in
                    Capsule()
                        .fill(share.emotion.color)
                        .frame(width: available * CGFloat(share.count) / CGFloat(total))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

#Preview {
    JournalView(viewModel: JournalViewModel(appState: .preview(), store: InMemoryDreamStore()))
}
