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
        if !trimmedQuery.isEmpty { return "Results" }
        return category == .popular ? "Most searched dreams" : category.title
    }

    /// On opening and on every category change; offline the cached symbols stay.
    func refresh() async {
        isLoading = catalog.symbols(in: category).isEmpty
        defer { isLoading = false }
        try? await catalog.refresh(category: category)
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
