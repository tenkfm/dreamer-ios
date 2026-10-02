import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class HomeViewModel {
    private let appState: AppState
    private let store: any DreamStore
    private let catalog: any SymbolCatalog
    /// The backend's insights; nil in mock mode, where they are computed from the stored dreams.
    private let insights: InsightStore?
    /// Dreams told but never read (nil in previews).
    private let drafts: DraftQueue?
    private let now: () -> Date
    private let calendar: Calendar

    init(appState: AppState, store: any DreamStore, catalog: any SymbolCatalog, insights: InsightStore? = nil,
         drafts: DraftQueue? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.appState = appState
        self.store = store
        self.catalog = catalog
        self.insights = insights
        self.drafts = drafts
        self.now = now
        var calendar = calendar
        calendar.firstWeekday = 2 // Week strip runs Monday..Sunday.
        self.calendar = calendar
    }

    // MARK: Greeting

    var greeting: String {
        let hour = calendar.component(.hour, from: now())
        let partOfDay = switch hour {
        case 4..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
        let name = appState.userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? partOfDay : "\(partOfDay), \(name)"
    }

    let subtitle = String(localized: "Tap to tell last night’s dream")

    // MARK: Week

    private var weekDates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now())?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var dreamsThisWeek: [DreamSummary] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now()) else { return [] }
        return store.summaries.filter { week.contains($0.createdAt) }
    }

    var weekDays: [WeekDayState] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        if let week = insights?.week {
            return week.days.enumerated().map { index, day in
                WeekDayState(id: index, letter: day.letter, isDone: day.caught, accessibilityName: formatter.string(from: day.date),
                             isPending: pendingDraft(on: day.date) != nil)
            }
        }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let dreams = dreamsThisWeek
        return weekDates.enumerated().map { index, day in
            WeekDayState(id: index,
                         letter: letters[index],
                         isDone: dreams.contains { calendar.isDate($0.createdAt, inSameDayAs: day) },
                         accessibilityName: formatter.string(from: day),
                         isPending: pendingDraft(on: day) != nil)
        }
    }

    /// The newest dream told that day and not read yet.
    private func pendingDraft(on day: Date) -> DreamDraft? {
        drafts?.pending.first { calendar.isDate($0.createdAt, inSameDayAs: day) }?.draft
    }

    /// A pending day of the week strip was tapped: read its dream.
    func readPending(_ day: WeekDayState) {
        let date: Date?
        if let days = insights?.week?.days {
            date = days.indices.contains(day.id) ? days[day.id].date : nil
        } else {
            date = weekDates.indices.contains(day.id) ? weekDates[day.id] : nil
        }
        guard let date, let draft = pendingDraft(on: date) else { return }
        appState.readDraft(draft)
    }

    var weekCaption: String {
        let count = insights?.week?.count ?? dreamsThisWeek.count
        return switch count {
        case 0: String(localized: "No dreams caught yet this week")
        case 1: "1 dream caught this week"
        default: "\(count) dreams caught this week"
        }
    }

    // MARK: Cards

    /// The backend's one or two cards (the last ones offline). Before any answer, the invitation, so
    /// the spot is never empty. Mock mode: the contract's examples on the seed dreams.
    var cards: [HomeCard] {
        guard let insights else { return mockCards }
        return insights.cards ?? [Self.invitation]
    }

    static let invitation = HomeCard(
        id: "invitation", kind: "record_prompt", overline: String(localized: "Your morning insight"), title: nil,
        text: String(localized: "Tell a dream each morning and your patterns will appear here."), imageURL: nil, action: nil)

    /// The copy of the contract's examples: a recap of the newest dream and a tip.
    private var mockCards: [HomeCard] {
        var cards: [HomeCard] = []
        if let dream = store.summaries.first {
            cards.append(HomeCard(id: "recap-\(dream.id)", kind: "dream_recap", overline: "Yesterday’s dream", title: dream.title,
                                  text: "What are you working toward right now?", imageURL: nil,
                                  action: .init(label: "Add a thought", destination: .dream(dream.id))))
        }
        cards.append(HomeCard(id: "tip-stay-still", kind: "tip", overline: "Dream tip", title: "Don’t move yet",
                              text: "When you wake, keep your eyes closed and stay as you are. Ask: “What was I just dreaming?” "
                                + "The first minute is when most dreams are won or lost.",
                              imageURL: nil,
                              action: .init(label: "Read more",
                                            destination: .article(URL(string: "https://dreamerapp.io/sleep/how-to-remember-dreams")!))))
        return cards
    }

    /// Pictures by card: the links are signed anew at every refresh, the card id is stable for the day.
    @ObservationIgnored private var cardImages: [String: UIImage] = [:]

    /// The card's picture, downloaded once a day; mock mode: the dream's asset.
    func image(for card: HomeCard) async -> UIImage? {
        if let cached = cardImages[card.id] { return cached }
        let image: UIImage?
        if let url = card.imageURL, insights != nil {
            guard let (data, response) = try? await APIClient.mediaSession.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            // Cards are about 100 pt wide (a banner is wider but short).
            image = await ImageDownsampler.decoded(from: data, pointSize: 360)
        } else if insights == nil, case .dream(let id)? = card.action?.destination, let dream = store.dream(id: id) {
            // Like the dream's hero: no image name means the placeholder.
            image = DreamImage.uiImage(named: dream.imageName)
        } else {
            image = nil
        }
        if let image { cardImages[card.id] = image }
        return image
    }

    /// Set to open an article in the in-app browser.
    var article: Article?

    struct Article: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// A card's button.
    func perform(_ action: HomeCard.Action) {
        switch action.destination {
        case .journal: appState.open(.journal)
        case .dream(let id): appState.openNotes(of: id)
        case .librarySymbol(let slug): appState.open(.library, route: .symbol(slug))
        case .record: startRecording()
        case .article(let url): article = Article(url: url)
        }
    }

    /// Changes when a dream is added or removed, so the insights are asked again.
    var dreamCount: Int { store.summaries.count }

    func refreshInsights() async {
        async let popular: Void = refreshPopularSymbols()
        await insights?.refresh()
        await popular
    }

    private func refreshPopularSymbols() async {
        try? await catalog.refresh(category: .popular)
    }

    // MARK: Library preview

    /// A symbol's picture from the backend (cached by the catalog); nil in mock mode, where the
    /// asset is shown.
    func imageData(for symbol: LibrarySymbol) async -> Data? {
        await catalog.imageData(for: symbol)
    }

    var featuredSymbols: [LibrarySymbol] {
        Array(catalog.symbols(in: .popular).prefix(6))
    }

    // MARK: Actions

    var isNightMode: Bool { appState.isNightMode }

    func openSettings() { appState.push(.settings, on: .today) }
    func toggleNightMode() { appState.toggleNightMode() }
    func startRecording() { appState.presentRecordFlow() }
    func seeAllSymbols() { appState.open(.library) }
    func open(_ symbol: LibrarySymbol) { appState.open(.library, route: .symbol(symbol.id)) }
}
