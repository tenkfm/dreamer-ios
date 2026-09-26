import Foundation
import Observation
import UIKit

/// A library symbol: the cached entry at once, then the full one (lenses, question, related).
@MainActor
@Observable
final class SymbolDetailViewModel {
    let slug: String
    private(set) var symbol: LibrarySymbol?
    private(set) var image: UIImage?
    private(set) var isLoading = false

    private let catalog: any SymbolCatalog
    private let appState: AppState
    private let analytics: any Analytics

    init(slug: String, catalog: any SymbolCatalog, appState: AppState, analytics: any Analytics = NoopAnalytics()) {
        self.slug = slug
        self.catalog = catalog
        self.appState = appState
        self.analytics = analytics
        symbol = catalog.symbol(id: slug)
    }

    /// Lenses with text, in the app's order.
    var lenses: [(lens: Lens, text: String)] {
        Lens.allCases.compactMap { lens in
            symbol?.lenses[lens].flatMap { $0.isEmpty ? nil : (lens, $0) }
        }
    }

    /// Related symbols the device knows (titles for the chips).
    var related: [LibrarySymbol] {
        (symbol?.related ?? []).map { catalog.symbol(id: $0) ?? LibrarySymbol(id: $0, title: $0.replacingOccurrences(of: "-", with: " ").capitalized, meaning: "", detail: "", categories: [], imageName: Dream.placeholderImageName, glyph: .sparkle) }
    }

    func appeared() async {
        analytics.track(.librarySymbolOpened(slug: slug))
        isLoading = symbol == nil
        if let full = try? await catalog.loadSymbol(id: slug) { symbol = full }
        isLoading = false
        if let symbol, let data = await catalog.imageData(for: symbol) { image = UIImage(data: data) }
    }

    func open(_ related: LibrarySymbol) {
        appState.push(.symbol(related.id), on: .library)
    }
}
