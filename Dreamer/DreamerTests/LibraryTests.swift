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
        // Two pages for the popular category, to follow the cursor.
        if category == .popular, cursor == nil { return LibraryPage(items: Array(items.prefix(2)), nextCursor: "p2") }
        if category == .popular { return LibraryPage(items: Array(items.dropFirst(2)), nextCursor: nil) }
        return LibraryPage(items: items, nextCursor: nil)
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
    @Test func aCategoryFollowsItsPagesAndWorksOfflineAfterwards() async throws {
        let file = tempFile()
        let remote = ScriptedLibrary()
        let catalog = APISymbolCatalog(remote: remote, fileURL: file)
        try await catalog.refresh(category: .popular)

        let popular = remote.symbols.filter { $0.categories.contains(.popular) }.map(\.id)
        #expect(catalog.symbols(in: .popular).map(\.id) == popular)
        #expect(remote.calls == ["list popular ", "list popular p2"])

        let offline = ScriptedLibrary()
        offline.goOffline()
        let relaunched = APISymbolCatalog(remote: offline, fileURL: file)
        await #expect(throws: APIError.offline) { try await relaunched.refresh(category: .popular) }
        #expect(relaunched.symbols(in: .popular).map(\.id) == popular)
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
