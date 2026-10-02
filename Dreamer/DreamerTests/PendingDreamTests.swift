import Foundation
import Testing
@testable import Dreamer

/// A dream told but never read (offline, no plan, a failure) shows in Journal and on Home's week,
/// and a tap reads it.
@MainActor
struct PendingDreamTests {
    private struct NeverSubmitter: DreamSubmitter {
        func submit(_ submission: DreamSubmission) async throws(APIError) -> Dream { throw .offline }
    }

    private let monday = ISO8601DateFormatter().date(from: "2026-09-28T09:00:00Z")!
    private var wednesday: Date { monday.addingTimeInterval(2 * 86_400) }

    private func queue(with transcript: String = "I was walking through a house I knew, but every room was new") throws -> DraftQueue {
        let queue = DraftQueue(container: try LocalStore.makeContainer(inMemory: true), submitter: NeverSubmitter(),
                               store: InMemoryDreamStore(seed: []), now: { wednesday })
        queue.save(DreamDraft(clientId: "6f1d2c3b-4a5e-4f60-8a7b-9c0d1e2f3a4b", transcript: transcript))
        return queue
    }

    private func appState(subscribed: Bool) -> AppState {
        let state = AppState(store: InMemoryPreferencesStore())
        if subscribed {
            state.signedIn(userID: "u", isNewUser: false)
            state.activateSubscription(.yearly)
        }
        return state
    }

    @Test func journalShowsItAtTheTopOfItsWeekWithItsOwnRow() throws {
        let drafts = try queue()
        let journal = JournalViewModel(appState: appState(subscribed: true), store: InMemoryDreamStore(seed: []),
                                       drafts: drafts, now: { wednesday })
        let row = try #require(journal.sections.first?.rows.first)
        #expect(journal.sections.first?.title == "This week")
        #expect(row.pendingDraft?.clientId == "6f1d2c3b-4a5e-4f60-8a7b-9c0d1e2f3a4b")
        #expect(row.title.hasPrefix("I was walking through a house"))
        #expect(row.title.hasSuffix("…"))
        #expect(!journal.isEmpty)
    }

    @Test func tappingItReadsItWithAPlanAndOffersThePlanWithout() throws {
        let drafts = try queue()
        let subscribed = appState(subscribed: true)
        let journal = JournalViewModel(appState: subscribed, store: InMemoryDreamStore(seed: []), drafts: drafts, now: { wednesday })
        journal.open(try #require(journal.sections.first?.rows.first))
        #expect(subscribed.isRecordFlowPresented)
        #expect(subscribed.draftToRead?.clientId == "6f1d2c3b-4a5e-4f60-8a7b-9c0d1e2f3a4b")

        let free = appState(subscribed: false)
        let freeJournal = JournalViewModel(appState: free, store: InMemoryDreamStore(seed: []), drafts: drafts, now: { wednesday })
        freeJournal.open(try #require(freeJournal.sections.first?.rows.first))
        #expect(free.isPaywallSheetPresented)
        #expect(!free.isRecordFlowPresented)
    }

    @Test func deletingItForgetsTheDraft() async throws {
        let drafts = try queue()
        let journal = JournalViewModel(appState: appState(subscribed: true), store: InMemoryDreamStore(seed: []),
                                       drafts: drafts, now: { wednesday })
        journal.askToDelete(try #require(journal.sections.first?.rows.first))
        await journal.confirmDelete()
        #expect(drafts.pendingCount == 0)
        #expect(journal.sections.isEmpty)
    }

    @Test func homeMarksItsDayAndReadsItOnTap() throws {
        let drafts = try queue()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let state = appState(subscribed: true)
        let home = HomeViewModel(appState: state, store: InMemoryDreamStore(seed: []), catalog: MockSymbolCatalog(),
                                 drafts: drafts, now: { wednesday }, calendar: calendar)
        let days = home.weekDays
        #expect(days.filter(\.isPending).map(\.id) == [2])
        home.readPending(days[2])
        #expect(state.draftToRead?.clientId == "6f1d2c3b-4a5e-4f60-8a7b-9c0d1e2f3a4b")
        #expect(state.isRecordFlowPresented)
    }
}

/// Home's "Dreamed about today" thumbs take their pictures from the catalog, like the Library.
@MainActor
struct HomeSymbolImageTests {
    final class PictureCatalog: SymbolCatalog {
        let symbols = MockData.librarySymbols
        private(set) var asked: [LibrarySymbol.ID] = []
        func symbols(in category: SymbolCategory) -> [LibrarySymbol] { symbols }
        func symbol(id: LibrarySymbol.ID) -> LibrarySymbol? { symbols.first { $0.id == id } }
        func refresh(category: SymbolCategory) async throws(APIError) {}
        func canLoadMore(category: SymbolCategory) -> Bool { false }
        func loadMore(category: SymbolCategory) async throws(APIError) {}
        func search(_ query: String) async throws(APIError) -> [LibrarySymbol] { [] }
        func loadSymbol(id: LibrarySymbol.ID) async throws(APIError) -> LibrarySymbol { symbols[0] }
        func imageData(for symbol: LibrarySymbol) async -> Data? {
            asked.append(symbol.id)
            return Data([1, 2, 3])
        }
    }

    @Test func thumbsAskTheCatalogForTheBackendPicture() async throws {
        let catalog = PictureCatalog()
        let home = HomeViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: InMemoryDreamStore(seed: []),
                                 catalog: catalog)
        let symbol = try #require(home.featuredSymbols.first)
        #expect(await home.imageData(for: symbol) == Data([1, 2, 3]))
        #expect(catalog.asked == [symbol.id])
    }
}
