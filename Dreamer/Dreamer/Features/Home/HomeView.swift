import SwiftUI

/// 07 Home (Today tab).
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(AppDependencies.self) private var dependencies

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: .top)
            ScrollView {
                VStack(spacing: 0) {
                    header.enterUp(0.1)
                    OrbButton(glyph: .mic, size: .home, accessibilityLabel: "Record last night’s dream") {
                        viewModel.startRecording()
                    }
                    .padding(.top, 6)
                    .enterUp(0.3)
                    greeting.enterUp(0.4)
                    if let drafts = dependencies.drafts, drafts.pendingCount > 0 {
                        DraftStatusPill(count: drafts.pendingCount, isSending: drafts.isSending)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    weekCard.padding(.top, 20).enterUp(0.55)
                    insightCard.padding(.top, 14).enterUp(0.7)
                    SectionHeader(title: "Dreamed about today", trailing: "See all") { viewModel.seeAllSymbols() }
                        .padding(.horizontal, DS.Space.screen)
                        .padding(.top, 22)
                        .enterUp(0.85)
                    thumbs.padding(.top, 4).enterUp(0.95)
                }
                .padding(.bottom, DS.Space.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isNightMode)
        // On opening and after every new or deleted dream.
        .task(id: viewModel.dreamCount) { await viewModel.refreshInsights() }
    }

    private var header: some View {
        HeaderBar {
            GlassIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") { viewModel.openSettings() }
        } center: {
            Logo()
        } trailing: {
            GlassIconButton(systemImage: viewModel.isNightMode ? "sun.max" : "moon",
                            accessibilityLabel: viewModel.isNightMode ? "Switch to day mode" : "Switch to night mode") {
                viewModel.toggleNightMode()
            }
        }
    }

    private var greeting: some View {
        VStack(spacing: 6) {
            Text(viewModel.greeting)
                .textStyle(.title)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.subtitle)
                .font(DreamerFont.ui(15, relativeTo: .body))
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Space.screen)
    }

    private var weekCard: some View {
        VStack(spacing: 6) {
            WeekStrip(days: viewModel.weekDays)
            Text(viewModel.weekCaption).textStyle(.secondary, color: DS.Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(radius: DS.Radius.cardLarge)
        .padding(.horizontal, DS.Space.screen)
    }

    @ViewBuilder private var insightCard: some View {
        if viewModel.showsInsightCard {
            insightCardContent
        }
    }

    private var insightCardContent: some View {
        Group {
            if let insight = viewModel.insight {
                InsightCard(overline: "Your morning insight", text: insight, buttonTitle: "See the pattern") {
                    viewModel.seePattern()
                }
            } else {
                InsightCard(overline: "Your morning insight", text: viewModel.insightPlaceholder)
            }
        }
        .padding(.horizontal, DS.Space.screen)
    }

    private var thumbs: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(viewModel.featuredSymbols.enumerated()), id: \.element.id) { index, symbol in
                    Button { viewModel.open(symbol) } label: {
                        DreamThumb(title: symbol.title, image: DreamImage.image(named: symbol.imageName), index: index)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, DS.Space.screen)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
}

/// Told dreams that have not reached the backend yet (offline, or waiting to be retried).
private struct DraftStatusPill: View {
    var count: Int
    var isSending: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSending {
                ProgressView().controlSize(.mini).tint(DS.Palette.icon)
            } else {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DS.Palette.icon)
            }
            Text(text)
                .font(DreamerFont.ui(12, relativeTo: .caption))
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 32)
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        if isSending { return count == 1 ? "Sending your dream…" : "Sending your dreams…" }
        return count == 1 ? "1 dream will be read when you’re online" : "\(count) dreams will be read when you’re online"
    }
}

#Preview {
    let state = AppState.preview()
    HomeView(viewModel: HomeViewModel(appState: state, store: InMemoryDreamStore(), catalog: MockSymbolCatalog()))
        .environment(AppDependencies.preview())
}
