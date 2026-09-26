import Foundation
import os
import Testing
@testable import Dreamer

/// Insight answers from a script; `failing` makes every call fail offline.
final class ScriptedInsights: InsightService, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(week: WeekInsight, morning: MorningInsight?, month: MonthInsight, failing: Bool, calls: Int)>

    init(week: WeekInsight, morning: MorningInsight?, month: MonthInsight) {
        state = OSAllocatedUnfairLock(initialState: (week, morning, month, false, 0))
    }

    var calls: Int { state.withLock { $0.calls } }
    func fail(_ failing: Bool) { state.withLock { $0.failing = failing } }

    func weekInsight() async throws(APIError) -> WeekInsight {
        try state.withLock { s -> Result<WeekInsight, APIError> in s.calls += 1; return s.failing ? .failure(.offline) : .success(s.week) }.get()
    }

    func morningInsight() async throws(APIError) -> MorningInsight? {
        try state.withLock { s -> Result<MorningInsight?, APIError> in s.calls += 1; return s.failing ? .failure(.offline) : .success(s.morning) }.get()
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
    static let morning = MorningInsight(symbol: "stairs", count: 3, text: "Stairs keep coming back this week.")
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
        let store = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, morning: InsightFixtures.morning,
                                                           month: InsightFixtures.month), fileURL: file)
        await store.refresh()
        #expect(store.week?.count == 2)
        #expect(store.morning?.symbol == "stairs")
        #expect(store.month?.topSymbol == "water")

        let offline = ScriptedInsights(week: InsightFixtures.week, morning: nil, month: InsightFixtures.emptyMonth)
        offline.fail(true)
        let relaunched = InsightStore(service: offline, fileURL: file)
        await relaunched.refresh()
        #expect(relaunched.snapshot == store.snapshot)
    }

    @Test func noMorningInsightIsAnAnswerToo() async {
        let store = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, morning: nil, month: InsightFixtures.month),
                                 fileURL: tempFile())
        await store.refresh()
        #expect(store.morning == nil)
        #expect(store.hasMorningAnswer)
    }

    @Test func signingOutForgetsThem() async {
        let file = tempFile()
        let store = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, morning: InsightFixtures.morning,
                                                           month: InsightFixtures.month), fileURL: file)
        await store.refresh()
        store.clear()
        #expect(store.week == nil)
        #expect(InsightStore(service: ScriptedInsights(week: InsightFixtures.week, morning: nil, month: InsightFixtures.month),
                             fileURL: file).week == nil)
    }
}

@MainActor
struct HomeInsightTests {
    private func makeHome(morning: MorningInsight?, month: MonthInsight = InsightFixtures.month,
                          dreams: [Dream] = MockData.seedDreams()) async -> HomeViewModel {
        let insights = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, morning: morning, month: month),
                                    fileURL: tempFile())
        await insights.refresh()
        return HomeViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: InMemoryDreamStore(seed: dreams),
                             catalog: MockSymbolCatalog(), insights: insights)
    }

    @Test func theWeekComesFromTheBackend() async {
        let home = await makeHome(morning: InsightFixtures.morning)
        #expect(home.weekDays.map(\.isDone) == [true, false, true, false, false, false, false])
        #expect(home.weekDays.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(home.weekCaption == "2 dreams caught this week")
        #expect(home.insight == "Stairs keep coming back this week.")
        #expect(home.showsInsightCard)
    }

    @Test func noMorningInsightHidesTheCard() async {
        let home = await makeHome(morning: nil)
        #expect(home.insight == nil)
        #expect(!home.showsInsightCard)
    }

    @Test func aNewUserIsInvited() async {
        let home = await makeHome(morning: nil, month: InsightFixtures.emptyMonth, dreams: [])
        #expect(home.showsInsightCard)
        #expect(home.insight == nil)
    }
}

@MainActor
struct JournalMonthTests {
    @Test func theSummaryComesFromTheMonthInsight() async {
        let insights = InsightStore(service: ScriptedInsights(week: InsightFixtures.week, morning: nil, month: InsightFixtures.month),
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
