import Foundation
import os
import SwiftData
import Testing
@testable import Dreamer

/// The journal endpoints from a script; records the calls.
final class ScriptedDreamRemote: DreamRemote, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(pages: [String: Result<DreamPage, APIError>], dreams: [UUID: Dream], calls: [String], deleteError: APIError?)>

    init(pages: [String: Result<DreamPage, APIError>] = [:], dreams: [Dream] = [], deleteError: APIError? = nil) {
        state = OSAllocatedUnfairLock(initialState: (pages, Dictionary(uniqueKeysWithValues: dreams.map { ($0.id, $0) }), [], deleteError))
    }

    var calls: [String] { state.withLock { $0.calls } }

    func setPage(_ cursor: String, _ result: Result<DreamPage, APIError>) {
        state.withLock { $0.pages[cursor] = result }
    }

    func listDreams(cursor: String?, limit: Int, emotion: Emotion?, query: String?) async throws(APIError) -> DreamPage {
        let key = cursor ?? "first"
        return try state.withLock { state in
            state.calls.append("list \(key)")
            return state.pages[key] ?? .failure(.offline)
        }.get()
    }

    func dream(id: UUID) async throws(APIError) -> Dream {
        try state.withLock { state -> Result<Dream, APIError> in
            state.calls.append("get")
            return state.dreams[id].map { .success($0) } ?? .failure(.server(.init(code: .notFound, message: "", status: 404)))
        }.get()
    }

    func deleteDream(id: UUID) async throws(APIError) {
        try state.withLock { state -> Result<Void, APIError> in
            state.calls.append("delete")
            return state.deleteError.map { .failure($0) } ?? .success(())
        }.get()
    }
}

@MainActor
struct CachedDreamStoreTests {
    private let seed = MockData.seedDreams()

    private func summaries(_ range: Range<Int>) -> [DreamSummary] {
        seed[range].map { var summary = DreamSummary($0); summary.assetName = nil; return summary }
    }

    private func container() throws -> ModelContainer {
        try LocalStore.makeContainer(inMemory: true)
    }

    @Test func theJournalShowsFromTheCacheAfterARelaunch() async throws {
        let container = try container()
        let remote = ScriptedDreamRemote(pages: ["first": .success(DreamPage(items: summaries(0..<3), nextCursor: nil))])
        let store = CachedDreamStore(container: container, remote: remote)
        try await store.refresh()

        // Offline next launch: the cached list is there before any network.
        let relaunched = CachedDreamStore(container: container, remote: ScriptedDreamRemote())
        #expect(relaunched.summaries.map(\.id) == seed[0..<3].map(\.id))
        await #expect(throws: APIError.offline) { try await relaunched.refresh() }
        #expect(relaunched.summaries.count == 3)
    }

    @Test func pagesFollowTheCursor() async throws {
        let remote = ScriptedDreamRemote(pages: [
            "first": .success(DreamPage(items: summaries(0..<2), nextCursor: "c2")),
            "c2": .success(DreamPage(items: summaries(2..<4), nextCursor: nil))
        ])
        let store = CachedDreamStore(container: try container(), remote: remote, pageSize: 2)
        try await store.refresh()
        #expect(store.canLoadMore)

        try await store.loadMore()

        #expect(store.summaries.map(\.id) == seed[0..<4].map(\.id))
        #expect(!store.canLoadMore)
        #expect(remote.calls == ["list first", "list c2"])
    }

    @Test func aDreamDeletedElsewhereDisappears() async throws {
        let container = try container()
        let remote = ScriptedDreamRemote(pages: ["first": .success(DreamPage(items: summaries(0..<3), nextCursor: nil))])
        let store = CachedDreamStore(container: container, remote: remote)
        try await store.refresh()
        store.save(seed[1])

        remote.setPage("first", .success(DreamPage(items: [summaries(0..<3)[0], summaries(0..<3)[2]], nextCursor: nil)))
        try await store.refresh()

        #expect(store.summaries.map(\.id) == [seed[0].id, seed[2].id])
        #expect(CachedDreamStore(container: container, remote: remote).dream(id: seed[1].id) == nil)
    }

    @Test func aNewDreamJoinsTheListAndTheCache() throws {
        let container = try container()
        let store = CachedDreamStore(container: container, remote: ScriptedDreamRemote())
        store.save(seed[3])
        store.save(seed[0])

        #expect(store.summaries.map(\.id) == [seed[0].id, seed[3].id])
        let relaunched = CachedDreamStore(container: container, remote: ScriptedDreamRemote())
        #expect(relaunched.dream(id: seed[0].id)?.transcript == seed[0].transcript)
        #expect(relaunched.summaries.count == 2)
    }

    @Test func openingADreamFetchesItInFull() async throws {
        let remote = ScriptedDreamRemote(dreams: [seed[0]])
        let store = CachedDreamStore(container: try container(), remote: remote)
        #expect(store.dream(id: seed[0].id) == nil)

        let dream = try await store.loadDream(id: seed[0].id)

        #expect(dream.id == seed[0].id)
        #expect(store.dream(id: seed[0].id) != nil)
    }

    @Test func deletingRemovesItEverywhere() async throws {
        let container = try container()
        let store = CachedDreamStore(container: container, remote: ScriptedDreamRemote())
        store.save(seed[0])

        try await store.delete(id: seed[0].id)

        #expect(store.summaries.isEmpty)
        #expect(CachedDreamStore(container: container, remote: ScriptedDreamRemote()).dream(id: seed[0].id) == nil)
    }

    @Test func aFailedDeleteKeepsTheDream() async throws {
        let store = CachedDreamStore(container: try container(), remote: ScriptedDreamRemote(deleteError: .offline))
        store.save(seed[0])
        await #expect(throws: APIError.offline) { try await store.delete(id: seed[0].id) }
        #expect(store.summaries.count == 1)
    }

    @Test func signingOutForgetsTheJournal() throws {
        let container = try container()
        let store = CachedDreamStore(container: container, remote: ScriptedDreamRemote())
        store.save(seed[0])
        store.deleteAll()
        let relaunched = CachedDreamStore(container: container, remote: ScriptedDreamRemote())
        #expect(relaunched.summaries.isEmpty)
        #expect(relaunched.dream(id: seed[0].id) == nil)
    }
}

@MainActor
struct JournalListTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 8))! }

    @Test func dreamsAreGroupedByWeek() {
        let store = InMemoryDreamStore(seed: MockData.seedDreams(now: now, calendar: calendar))
        let viewModel = JournalViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: store,
                                         now: { now }, calendar: calendar)
        let titles = viewModel.sections.map(\.title)
        #expect(titles.first == "This week")
        #expect(titles.dropFirst().first == "Last week")
        #expect(Set(titles).count == titles.count)
        #expect(viewModel.sections.flatMap(\.rows).count == store.summaries.count)
    }

    @Test func deletingAsksFirst() async {
        let store = InMemoryDreamStore()
        let viewModel = JournalViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: store)
        let row = viewModel.sections[0].rows[0]

        viewModel.askToDelete(row)
        #expect(store.summaries.contains { $0.id == row.id })

        await viewModel.confirmDelete()
        #expect(!store.summaries.contains { $0.id == row.id })
        #expect(viewModel.deleteCandidate == nil)
        #expect(viewModel.haptic?.kind == .success)
    }

    @Test func weekRangesReadNaturally() {
        let formatter = DreamDateFormatter(calendar: calendar)
        let sep8 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let sep14 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))!
        let aug31 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        #expect(formatter.range(from: sep8, to: sep14) == "Sep 7 - 13")
        #expect(formatter.range(from: aug31, to: calendar.date(byAdding: .day, value: 6, to: aug31)!) == "Aug 31 - Sep 6")
    }
}

@MainActor
struct JournalSearchTests {
    /// Answers searches after a moment, and records them.
    final class SearchingStore: DreamStore {
        let base = InMemoryDreamStore()
        var searches: [String] = []
        var failure: APIError?
        var summaries: [DreamSummary] { base.summaries }
        var canLoadMore: Bool { false }
        func refresh() async throws(APIError) {}
        func loadMore() async throws(APIError) {}
        func dream(id: Dream.ID) -> Dream? { base.dream(id: id) }
        func loadDream(id: Dream.ID) async throws(APIError) -> Dream { try await base.loadDream(id: id) }
        func save(_ dream: Dream) { base.save(dream) }
        func delete(id: Dream.ID) async throws(APIError) { try await base.delete(id: id) }
        func deleteAll() { base.deleteAll() }
        func search(query: String?, emotion: Emotion?) async throws(APIError) -> [DreamSummary] {
            searches.append("\(query ?? "-")|\(emotion?.rawValue ?? "-")")
            if let failure { throw failure }
            return try await base.search(query: query, emotion: emotion)
        }
    }

    private func makeViewModel(_ store: SearchingStore) -> JournalViewModel {
        let viewModel = JournalViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: store,
                                         searchDebounce: .milliseconds(20))
        viewModel.toggleSearch()
        return viewModel
    }

    @Test func typingAsksTheServerOnceAfterAPause() async throws {
        let store = SearchingStore()
        let viewModel = makeViewModel(store)
        viewModel.query = "s"
        viewModel.query = "st"
        viewModel.query = "stairs"
        try await Task.sleep(for: .milliseconds(120))

        #expect(store.searches == ["stairs|-"])
        let rows = viewModel.sections.flatMap(\.rows)
        #expect(rows.contains { $0.title == "The house with endless stairs" })
        #expect(rows.allSatisfy { $0.snippet?.localizedCaseInsensitiveContains("**stairs**") == true })
    }

    @Test func searchFindsTheInterpretationToo() async throws {
        let store = SearchingStore()
        let viewModel = makeViewModel(store)
        // "roots" is only in the interpretation of the stairs dream.
        viewModel.query = "roots"
        try await Task.sleep(for: .milliseconds(120))
        #expect(!viewModel.sections.isEmpty)
    }

    @Test func emotionChipsFilter() async throws {
        let store = SearchingStore()
        let viewModel = makeViewModel(store)
        viewModel.toggleEmotionFilter(.joy)
        try await Task.sleep(for: .milliseconds(120))

        #expect(store.searches == ["-|joy"])
        #expect(viewModel.sections.flatMap(\.rows).allSatisfy { row in store.base.dream(id: row.id)?.emotions.contains(.joy) == true })
        viewModel.toggleEmotionFilter(.joy)
        #expect(viewModel.emotionFilter == nil)
    }

    @Test func offlineSearchFiltersTheDevice() async throws {
        let store = SearchingStore()
        store.failure = .offline
        let viewModel = makeViewModel(store)
        viewModel.query = "frozen"
        try await Task.sleep(for: .milliseconds(120))
        #expect(viewModel.sections.flatMap(\.rows).map(\.title) == ["Flying over a frozen lake"])
    }

    @Test func closingSearchShowsTheWholeJournal() {
        let store = SearchingStore()
        let viewModel = makeViewModel(store)
        viewModel.query = "zzz"
        viewModel.toggleSearch()
        #expect(viewModel.sections.flatMap(\.rows).count == store.summaries.count)
    }
}
