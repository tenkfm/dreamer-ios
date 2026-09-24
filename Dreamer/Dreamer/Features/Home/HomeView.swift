import SwiftUI

/// 07 Home (Today tab).
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var nightModeTaps = 0

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
        .sensoryFeedback(.impact(weight: .light), trigger: nightModeTaps)
    }

    private var header: some View {
        HeaderBar {
            GlassIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") { viewModel.openSettings() }
        } center: {
            Logo()
        } trailing: {
            // Night mode arrives in a later phase; for now the button only answers with a haptic.
            GlassIconButton(systemImage: "moon", accessibilityLabel: "Night mode") { nightModeTaps += 1 }
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

    private var insightCard: some View {
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

#Preview {
    let state = AppState.preview()
    HomeView(viewModel: HomeViewModel(appState: state, store: InMemoryDreamStore(), catalog: MockSymbolCatalog()))
}
