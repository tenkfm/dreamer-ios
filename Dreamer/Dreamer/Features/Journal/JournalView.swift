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
        }
        .animation(.soft(0.4), value: viewModel.isSearching)
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
        if !viewModel.thisMonthRows.isEmpty {
            section(title: "This month", rows: viewModel.thisMonthRows, delay: 0.45)
        }
        if !viewModel.earlierRows.isEmpty {
            section(title: "Earlier", rows: viewModel.earlierRows, delay: 0.6)
        }
    }

    private func section(title: String, rows: [JournalViewModel.Row], delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title)
            VStack(spacing: DS.Space.stack) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { viewModel.open(row) } label: {
                        DreamRow(title: row.title,
                                 date: row.dateText,
                                 image: DreamImage.image(named: row.imageName),
                                 emotion: row.emotion.map { ($0.title, $0.color) })
                    }
                    .buttonStyle(PressableButtonStyle())
                    .enterUp(delay + Double(min(index, 5)) * 0.1)
                }
            }
        }
        .padding(.top, 30)
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
