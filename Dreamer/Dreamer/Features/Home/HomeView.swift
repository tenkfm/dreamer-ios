import SwiftUI

/// 07 Home (Today tab).
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(ReminderController.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase

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
                    cards.padding(.top, 14).enterUp(0.7)
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
        // Every time Home shows (a tab switch, back from a pushed screen) and after every new or
        // deleted dream: the cards follow the hour and the journal.
        .task(id: viewModel.dreamCount) { await viewModel.refreshInsights() }
        // Back from the background: a Home left open overnight still shows the morning's cards.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshInsights() } }
        }
        .sheet(item: $viewModel.article) { article in
            SafariView(url: article.url).ignoresSafeArea()
        }
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

    /// One or two cards, never none.
    private var cards: some View {
        VStack(spacing: DS.Space.stack) {
            ForEach(viewModel.cards) { card in
                HomeCardView(card: card, viewModel: viewModel)
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .animation(.soft(0.4), value: viewModel.cards)
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

/// A Home card: overline, title, text, its picture and the button. A wide picture (a Library
/// tile) is a banner on top, a tall one (a dream) sits beside the text; without one, the sparkle.
private struct HomeCardView: View {
    var card: HomeCard
    var viewModel: HomeViewModel
    @State private var image: UIImage?

    private var isWide: Bool { image.map { $0.size.width > $0.size.height } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image, isWide {
                // The card sets the width: a filled image on its own would widen it.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.option, style: .continuous))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 14) {
                if image == nil {
                    TwinklingSparkle(size: 18).padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Overline(text: card.overline)
                    if let title = card.title {
                        Text(title).textStyle(.heading).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(card.text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let image, !isWide {
                    Color.clear
                        .frame(width: 64, height: 96)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.option, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            if let action = card.action {
                PillButton(title: action.label) { viewModel.perform(action) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, -4)
            }
        }
        .padding(.horizontal, DS.Space.cardPaddingLarge)
        .padding(.vertical, 18)
        .glassCard(radius: DS.Radius.cardLarge)
        .task(id: card.imageURL) {
            let loaded = await viewModel.image(for: card)
            withAnimation(.soft(0.4)) { image = loaded }
        }
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
                guard let data = await viewModel.imageData(for: symbol) else { return }
                image = await ImageDownsampler.decoded(from: data, pointSize: 100)
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
