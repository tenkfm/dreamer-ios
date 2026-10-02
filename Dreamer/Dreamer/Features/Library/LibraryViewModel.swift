import Foundation
import Observation

/// 13 Library: categories from the backend (cached, so it works offline), server search.
@MainActor
@Observable
final class LibraryViewModel {
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    var category: SymbolCategory = .popular
    /// The first load of a category with nothing cached yet.
    private(set) var isLoading = false
    /// The next page is on its way (the spinner under the grid).
    private(set) var isLoadingMore = false
    private(set) var searchResults: [LibrarySymbol]?

    let categories = SymbolCategory.allCases

    private let appState: AppState
    private let catalog: any SymbolCatalog
    private let searchDebounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(appState: AppState, catalog: any SymbolCatalog, searchDebounce: Duration = .milliseconds(300)) {
        self.appState = appState
        self.catalog = catalog
        self.searchDebounce = searchDebounce
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var symbols: [LibrarySymbol] {
        let trimmed = trimmedQuery
        if !trimmed.isEmpty {
            // Search covers the whole library, not only the selected category.
            return searchResults ?? localMatches(trimmed)
        }
        return catalog.symbols(in: category)
    }

    var sectionTitle: String {
        if !trimmedQuery.isEmpty { return String(localized: "Results") }
        return category == .popular ? String(localized: "Most searched dreams") : category.title
    }

    /// On opening and on every category change; offline the cached symbols stay.
    func refresh() async {
        isLoading = catalog.symbols(in: category).isEmpty
        defer { isLoading = false }
        try? await catalog.refresh(category: category)
    }

    /// More pages of the category, not while searching (search is one page).
    var canLoadMore: Bool { trimmedQuery.isEmpty && catalog.canLoadMore(category: category) }

    /// What the list shows (category or search); the grid animates when this changes, not when a
    /// page is appended.
    var listIdentity: String { "\(category.rawValue)|\(trimmedQuery)" }

    /// A tile came into view: four from the end, the next page starts, so it is there before the
    /// scroll reaches the bottom.
    func symbolAppeared(_ symbol: LibrarySymbol) async {
        let list = symbols
        guard let index = list.firstIndex(where: { $0.id == symbol.id }), index >= list.count - 4,
              canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        try? await catalog.loadMore(category: category)
    }

    func imageData(for symbol: LibrarySymbol) async -> Data? {
        await catalog.imageData(for: symbol)
    }

    func open(_ symbol: LibrarySymbol) {
        appState.push(.symbol(symbol.id), on: .library)
    }

    // MARK: Search

    private func localMatches(_ query: String) -> [LibrarySymbol] {
        catalog.symbols.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.meaning.localizedCaseInsensitiveContains(query)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchResults = nil
        let query = trimmedQuery
        guard !query.isEmpty else { return }
        searchTask = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled, let self else { return }
            // Offline: the cached symbols are searched instead.
            let results = (try? await self.catalog.search(query)) ?? self.localMatches(query)
            guard !Task.isCancelled else { return }
            self.searchResults = results
        }
    }
}
