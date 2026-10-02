import Foundation
import os
import Testing
@testable import Dreamer

/// Insight answers from a script; `failing` makes every call fail offline.
final class ScriptedInsights: InsightService, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(week: WeekInsight, cards: [HomeCard], month: MonthInsight, failing: Bool, calls: Int)>

    init(week: WeekInsight, cards: [HomeCard] = InsightFixtures.cards, month: MonthInsight) {
        state = OSAllocatedUnfairLock(initialState: (week, cards, month, false, 0))
    }

    var calls: Int { state.withLock { $0.calls } }
    func fail(_ failing: Bool) { state.withLock { $0.failing = failing } }

    func weekInsight() async throws(APIError) -> WeekInsight {
        try state.withLock { s -> Result<WeekInsight, APIError> in s.calls += 1; return s.failing ? .failure(.offline) : .success(s.week) }.get()
    }

    func homeCards() async throws(APIError) -> [HomeCard] {
        try state.withLock { s -> Result<[HomeCard], APIError> in s.calls += 1; return s.failing ? .failure(.offline) : .success(s.cards) }.get()
    }

    func monthInsight(month: String?) async throws(APIError) -> MonthInsight {
        try state.withLock { s -> Result<MonthInsight, APIError> in s.calls += 1; return s.failing ? .failure(.offline) : .success(s.month) }.get()
    }
}

enum InsightFixtures {
    static let calendar = Calendar(identifier: .gregorian)
    static func day(_ n: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: n))! }

    static let week = WeekInsight(days: (21...27).enumerated().map { index, n in
        WeekInsight.Day(date: day(n), letter: ["M", "T", "W", "T", "F", "S", "S"][index], caught: [21, 23].contains(n), isToday: n == 25)
    }, count: 2)
    static let cards = [
        HomeCard(id: "pattern-stairs", kind: "pattern", overline: "This week", title: nil, text: "Stairs keep coming back this week.",
                 imageURL: nil, action: .init(label: "See the pattern", destination: .journal)),
        HomeCard(id: "tip-stay-still", kind: "tip", overline: "Dream tip", title: "Don’t move yet", text: "Keep your eyes closed.",
                 imageURL: nil, action: .init(label: "Read more", destination: .article(URL(string: "https://dreamerapp.io/sleep")!)))
    ]
    static let month = MonthInsight(month: "2026-09", monthName: "September", dreamCount: 9, nightsSoFar: 25, topSymbol: "water",
                                    emotions: [.init(emotion: .calm, share: 0.25), .init(emotion: .joy, share: 0.75), .init(emotion: .fear, share: 0)],
                                    recurringSymbols: [.init(keyword: "water", count: 4)])
    static let emptyMonth = MonthInsight(month: "2026-09", monthName: "September", dreamCount: 0, nightsSoFar: 25, topSymbol: nil,
                                         emotions: [], recurringSymbols: [])
}

private func tempFile() -> URL {
    URL.temporaryDirectory.appending(path: "insights-\(UUID().uuidString).json")
}

@MainActor
struct InsightStoreTests {
    @Test func insightsAreKeptForTheNextLaunch() async {
        let file = tempFile()
        let store = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, month: InsightFixtures.month), fileURL: file)
        await store.refresh()
        #expect(store.week?.count == 2)
        #expect(store.cards?.map(\.id) == ["pattern-stairs", "tip-stay-still"])
        #expect(store.month?.topSymbol == "water")

        let offline = ScriptedInsights(week: InsightFixtures.week, month: InsightFixtures.emptyMonth)
        offline.fail(true)
        let relaunched = InsightStore(service: offline, fileURL: file)
        await relaunched.refresh()
        #expect(relaunched.snapshot == store.snapshot)
    }

    /// "Never none" is the contract; an empty answer anyway keeps the last cards instead of a gap.
    @Test func anEmptyAnswerKeepsTheLastCards() async {
        let file = tempFile()
        let store = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, month: InsightFixtures.month), fileURL: file)
        await store.refresh()
        let empty = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, cards: [], month: InsightFixtures.month), fileURL: file)
        await empty.refresh()
        #expect(empty.cards?.count == 2)
    }

    @Test func signingOutForgetsThem() async {
        let file = tempFile()
        let store = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, month: InsightFixtures.month), fileURL: file)
        await store.refresh()
        store.clear()
        #expect(store.week == nil)
        #expect(InsightStore(service: ScriptedInsights(week: InsightFixtures.week, month: InsightFixtures.month),
                             fileURL: file).week == nil)
    }
}

@MainActor
struct HomeInsightTests {
    private func makeHome(cards: [HomeCard] = InsightFixtures.cards, refreshed: Bool = true,
                          appState: AppState = AppState(store: InMemoryPreferencesStore())) async -> HomeViewModel {
        let insights = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, cards: cards, month: InsightFixtures.month),
                                    fileURL: tempFile())
        if refreshed { await insights.refresh() }
        return HomeViewModel(appState: appState, store: InMemoryDreamStore(seed: MockData.seedDreams()),
                             catalog: MockSymbolCatalog(), insights: insights)
    }

    @Test func theWeekAndTheCardsComeFromTheBackend() async {
        let home = await makeHome()
        #expect(home.weekDays.map(\.isDone) == [true, false, true, false, false, false, false])
        #expect(home.weekDays.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(home.weekCaption == "2 dreams caught this week")
        #expect(home.cards.map(\.id) == ["pattern-stairs", "tip-stay-still"])
    }

    /// Before the first answer (a first launch offline) the spot is not empty.
    @Test func beforeAnyAnswerTheInvitationShows() async {
        let home = await makeHome(refreshed: false)
        #expect(home.cards == [HomeViewModel.invitation])
    }

    @Test func eachButtonOpensItsPlace() async throws {
        let appState = AppState(store: InMemoryPreferencesStore())
        let home = await makeHome(appState: appState)
        let dreamID = UUID()

        home.perform(.init(label: "See", destination: .journal))
        #expect(appState.selectedTab == .journal)

        home.perform(.init(label: "Add a thought", destination: .dream(dreamID)))
        #expect(appState.selectedTab == .today)
        #expect(appState.path(for: .today).last == .interpretation(dreamID))
        #expect(appState.notesFocus == dreamID)

        home.perform(.init(label: "Open", destination: .librarySymbol(slug: "stairs")))
        #expect(appState.selectedTab == .library)
        #expect(appState.path(for: .library).last == .symbol("stairs"))

        let article = try #require(URL(string: "https://dreamerapp.io/sleep/how-to-remember-dreams"))
        home.perform(.init(label: "Read more", destination: .article(article)))
        #expect(home.article?.url == article)
    }

    @Test func recordNeedsAccessLikeTheMic() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.enterMainForTesting()
        let home = await makeHome(appState: appState)
        home.perform(.init(label: "Tell it", destination: .record))
        #expect(appState.isRecordFlowPresented)
    }
}

@MainActor
struct HomeCardMappingTests {
    @Test func theContractExampleMaps() async throws {
        let cards = try await ContractExamples.client("homeCards", status: 200).homeCards()
        #expect(cards.count == 2)
        #expect(cards[0].action?.destination == .dream(try #require(UUID(uuidString: "0d4b8a3e-6f0e-4d8e-9a43-2b8f5a1c7e10"))))
        #expect(cards[0].imageURL != nil)
        #expect(cards[1].title == "Don’t move yet")
        #expect(cards[1].action?.label == "Read more")
    }

    /// The point of plain strings: a kind or a target this build has never seen still shows the
    /// card; only the button it cannot open is left out.
    @Test func unknownKindsShowAndUnknownTargetsLoseTheirButton() async throws {
        let body = #"""
        {"cards":[
          {"id":"a","kind":"moon_phase","overline":"Tonight","title":null,"text":"A new moon.","imageUrl":null,
           "action":{"label":"Look","target":"sky_map","dreamId":null,"slug":null,"url":null},"later":1},
          {"id":"b","kind":"symbol_of_day","overline":"Symbol of the day","title":"Water","text":"Feelings.",
           "imageUrl":"https://media.example.com/water.webp",
           "action":{"label":"Open","target":"library_symbol","dreamId":null,"slug":"water","url":null}}
        ]}
        """#
        let client = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in .json(200, body) }.0
        let cards = try await client.homeCards()
        #expect(cards.map(\.kind) == ["moon_phase", "symbol_of_day"])
        #expect(cards[0].action == nil)
        #expect(cards[1].action?.destination == .librarySymbol(slug: "water"))
    }

    @Test func aTargetWithoutWhatItNeedsHasNoButton() {
        #expect(HomeCard.Destination(target: "dream", dreamID: "not-a-uuid", slug: nil, url: nil) == nil)
        #expect(HomeCard.Destination(target: "library_symbol", dreamID: nil, slug: "", url: nil) == nil)
        #expect(HomeCard.Destination(target: "article", dreamID: nil, slug: nil, url: "javascript:alert(1)") == nil)
        #expect(HomeCard.Destination(target: "record", dreamID: nil, slug: nil, url: nil) == .record)
    }
}

@MainActor
struct JournalMonthTests {
    @Test func theSummaryComesFromTheMonthInsight() async {
        let insights = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, month: InsightFixtures.month),
                                    fileURL: tempFile())
        await insights.refresh()
        let journal = JournalViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: InMemoryDreamStore(),
                                       insights: insights)

        let summary = journal.summary
        #expect(summary.title == "Your September")
        #expect(summary.dreamCount == 9)
        #expect(summary.mostFrequentSymbol == "water")
        #expect(summary.distribution.map(\.emotion) == [.joy, .calm])
        #expect(abs(summary.ringProgress - 9.0 / 25.0) < 0.001)
    }
}
