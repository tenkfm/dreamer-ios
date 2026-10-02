import SwiftUI

/// 07 Home (Today tab).
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(ReminderController.self) private var reminders

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
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isNightMode)
        // On opening and after every new or deleted dream.
        .task(id: viewModel.dreamCount) { await viewModel.refreshInsights() }
        .trackScreen(.home)
        // The first Home after onboarding offers the morning reminder (once).
        .task {
            // The tracking question first (placement A), then the reminder offer after it.
            dependencies.trackingConsent.moment(.firstHome)
            await reminders.homeAppeared()
        }
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
            WeekStrip(days: viewModel.weekDays, onPendingTap: viewModel.readPending)
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
                        SymbolThumb(symbol: symbol, index: index, viewModel: viewModel)
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

/// A Library symbol on Home: its picture from the backend, like the Library's tiles, with the
/// bundled one until it arrives (and in mock mode).
private struct SymbolThumb: View {
    var symbol: LibrarySymbol
    var index: Int
    var viewModel: HomeViewModel
    @State private var image: UIImage?

    var body: some View {
        DreamThumb(title: symbol.title,
                   image: image.map(Image.init(uiImage:)) ?? DreamImage.image(named: symbol.imageName),
                   index: index)
            .task(id: symbol.imageURL) {
                // Thumbs are 84 x 94 pt.
                image = await viewModel.imageData(for: symbol).flatMap { ImageDownsampler.image(from: $0, pointSize: 100) }
            }
    }
}

#Preview {
    let state = AppState.preview()
    HomeView(viewModel: HomeViewModel(appState: state, store: InMemoryDreamStore(), catalog: MockSymbolCatalog()))
        .environment(AppDependencies.preview())
        .environment(ReminderController.preview)
        .environment(AppLock(appState: .preview(), authenticator: MockAuthenticator()))
}
