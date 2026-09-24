import Foundation
import Observation

/// 13 Library: search by title and filter by category.
@MainActor
@Observable
final class LibraryViewModel {
    var query = ""
    var category: SymbolCategory = .popular

    let categories = SymbolCategory.allCases

    private let appState: AppState
    private let catalog: any SymbolCatalog

    init(appState: AppState, catalog: any SymbolCatalog) {
        self.appState = appState
        self.catalog = catalog
    }

    var symbols: [LibrarySymbol] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // Search covers the whole library, not only the selected category.
            return catalog.symbols.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) || $0.meaning.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return catalog.symbols.filter { $0.categories.contains(category) }
    }

    var sectionTitle: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "Results" }
        return category == .popular ? "Most searched dreams" : category.title
    }

    func open(_ symbol: LibrarySymbol) {
        appState.push(.symbol(symbol.id), on: .library)
    }
}
