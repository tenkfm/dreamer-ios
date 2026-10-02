import Foundation
import os
import Testing
@testable import Dreamer

/// Library answers from fixed symbols; can go offline.
final class ScriptedLibrary: LibraryRemote, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (offline: false, calls: [String]()))
    let symbols = MockData.librarySymbols

    var calls: [String] { state.withLock { $0.calls } }
    func goOffline() { state.withLock { $0.offline = true } }

    func librarySymbols(query: String?, category: SymbolCategory?, cursor: String?, limit: Int) async throws(APIError) -> LibraryPage {
        let offline = state.withLock { s -> Bool in s.calls.append("list \(query ?? category?.rawValue ?? "-") \(cursor ?? "")"); return s.offline }
        if offline { throw APIError.offline }
        var items = symbols.map { symbol -> LibrarySymbol in
            var entry = symbol
            entry.lenses = [:]
            entry.related = []
            return entry
        }
        if let category { items = items.filter { $0.categories.contains(category) } }
        if let query { items = items.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        // Pages of `limit`; the cursor is the offset of the next one.
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(items.count, start + limit)
        return LibraryPage(items: Array(items[start..<end]), nextCursor: end < items.count ? String(end) : nil)
    }

    func librarySymbol(slug: String) async throws(APIError) -> LibrarySymbol {
        let offline = state.withLock { s -> Bool in s.calls.append("get \(slug)"); return s.offline }
        if offline { throw APIError.offline }
        guard var symbol = symbols.first(where: { $0.id == slug }) else {
            throw APIError.server(.init(code: .notFound, message: "", status: 404))
        }
        symbol.lenses = [.psychology: "A path you walk slowly.", .spiritual: "An ascent.", .dreamBook: ""]
        symbol.related = ["dog", "unknown-slug"]
        symbol.question = "Where are you going?"
        return symbol
    }
}

private func tempFile() -> URL {
    URL.temporaryDirectory.appending(path: "library-\(UUID().uuidString).json")
}

@MainActor
struct APISymbolCatalogTests {
    /// "Popular" is the whole library, a page at a time; later pages come as the grid scrolls.
    @Test func popularPagesThroughTheWholeLibraryAndWorksOfflineAfterwards() async throws {
        let file = tempFile()
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: file, pageSize: 5)
        let all = remote.symbols.map(\.id)

        try await catalog.refresh(category: .popular)
        #expect(catalog.symbols(in: .popular).map(\.id) == Array(all.prefix(5)))
        #expect(catalog.canLoadMore(category: .popular))

        while catalog.canLoadMore(category: .popular) { try await catalog.loadMore(category: .popular) }
        #expect(catalog.symbols(in: .popular).map(\.id) == all)
        #expect(remote.calls == ["list - ", "list - 5", "list - 10"])

        let offline = ScriptedLibrary()
        offline.goOffline()
        let relaunched = APISymbolCatalog(remote: offline, fileURL: file, pageSize: 5)
        await #expect(throws: APIError.offline) { try await relaunched.refresh(category: .popular) }
        #expect(relaunched.symbols(in: .popular).map(\.id) == all)
    }

    /// Back from a symbol (or Home refreshing Popular): the pages already loaded stay, so the
    /// scroll position does not jump.
    @Test func refreshingKeepsThePagesLoadedSince() async throws {
        let catalog = APISymbolCatalog(remote: ScriptedLibrary(), fileURL: tempFile(), pageSize: 5)
        try await catalog.refresh(category: .popular)
        try await catalog.loadMore(category: .popular)
        #expect(catalog.symbols(in: .popular).count == 10)
        try await catalog.refresh(category: .popular)
        #expect(catalog.symbols(in: .popular).count == 10)
        #expect(catalog.canLoadMore(category: .popular))
    }

    @Test func aShelfAsksForItsCategory() async throws {
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: tempFile(), pageSize: 20)
        try await catalog.refresh(category: .animals)
        #expect(remote.calls == ["list animals "])
        #expect(catalog.symbols(in: .animals).allSatisfy { $0.categories.contains(.animals) })
        #expect(!catalog.canLoadMore(category: .animals))
    }

    @Test func theLastTileLoadsTheNextPage() async throws {
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: tempFile(), pageSize: 5)
        let library = LibraryViewModel(appState: AppState(store: InMemoryPreferencesStore()), catalog: catalog)
        await library.refresh()
        #expect(library.symbols.count == 5)
        await library.symbolAppeared(library.symbols[0])
        #expect(library.symbols.count == 5)
        await library.symbolAppeared(try #require(library.symbols.last))
        #expect(library.symbols.count == 10)
    }

    @Test func anOpenedSymbolKeepsItsLensesAcrossListRefreshes() async throws {
        let catalog = APISymbolCatalog(remote: ScriptedLibrary(), fileURL: tempFile())
        let slug = MockData.librarySymbols[0].id
        _ = try await catalog.loadSymbol(id: slug)
        try await catalog.refresh(category: .popular)
        #expect(catalog.symbol(id: slug)?.lenses[.psychology] == "A path you walk slowly.")
    }

    @Test func searchAsksTheServerAndRemembersTheResults() async throws {
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: tempFile())
        let results = try await catalog.search("teeth")
        #expect(results.map(\.id) == ["teeth"])
        #expect(catalog.symbol(id: "teeth") != nil)
    }
}

@MainActor
struct LibraryScreenTests {
    @Test func searchGoesToTheServerAfterAPause() async throws {
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: tempFile())
        let viewModel = LibraryViewModel(appState: AppState(store: InMemoryPreferencesStore()), catalog: catalog,
                                         searchDebounce: .milliseconds(20))
        viewModel.query = "t"
        viewModel.query = "teeth"
        try await Task.sleep(for: .milliseconds(120))

        #expect(viewModel.symbols.map(\.id) == ["teeth"])
        #expect(remote.calls == ["list teeth "])
        #expect(viewModel.sectionTitle == "Results")
    }

    @Test func offlineSearchUsesTheCache() async throws {
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: tempFile())
        try await catalog.refresh(category: .animals)
        remote.goOffline()
        let viewModel = LibraryViewModel(appState: AppState(store: InMemoryPreferencesStore()), catalog: catalog,
                                         searchDebounce: .milliseconds(5))
        viewModel.query = "dog"
        try await Task.sleep(for: .milliseconds(80))
        #expect(viewModel.symbols.map(\.id) == ["dog"])
    }

    @Test func aNewCategoryShowsASpinnerOnlyWithoutCache() async {
        let viewModel = LibraryViewModel(appState: AppState(store: InMemoryPreferencesStore()),
                                         catalog: APISymbolCatalog(remote: ScriptedLibrary(), fileURL: tempFile()))
        viewModel.category = .animals
        await viewModel.refresh()
        #expect(!viewModel.isLoading)
        #expect(viewModel.symbols.map(\.id) == ["snakes", "dog"])
    }
}

@MainActor
struct SymbolDetailTests {
    @Test func openingASymbolLoadsItInFullAndIsTracked() async throws {
        let analytics = RecordingAnalytics()
        let catalog = APISymbolCatalog(remote: ScriptedLibrary(), fileURL: tempFile())
        try await catalog.refresh(category: .animals)
        let slug = MockData.librarySymbols[0].id
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = SymbolDetailViewModel(slug: slug, catalog: catalog, appState: appState, analytics: analytics)

        await viewModel.appeared()

        #expect(analytics.events == [.librarySymbolOpened(slug: slug)])
        #expect(viewModel.lenses.map(\.lens) == [.psychology, .spiritual])
        #expect(viewModel.symbol?.question == "Where are you going?")
        #expect(viewModel.related.map(\.title) == ["Dogs", "Unknown Slug"])

        viewModel.open(viewModel.related[0])
        #expect(appState.paths[.library]?.last == .symbol("dog"))
    }

    @Test func offlineWithoutCacheSaysSo() async {
        let remote = ScriptedLibrary()
        remote.goOffline()
        let viewModel = SymbolDetailViewModel(slug: "teeth", catalog: APISymbolCatalog(remote: remote, fileURL: tempFile()),
                                              appState: AppState(store: InMemoryPreferencesStore()))
        await viewModel.appeared()
        #expect(viewModel.symbol == nil)
        #expect(!viewModel.isLoading)
    }
}
