import CryptoKit
import Foundation
import Observation

/// What the library needs from the backend.
protocol LibraryRemote: Sendable {
    func librarySymbols(query: String?, category: SymbolCategory?, cursor: String?, limit: Int) async throws(APIError) -> LibraryPage
    func librarySymbol(slug: String) async throws(APIError) -> LibrarySymbol
}

extension APIClient: LibraryRemote {}

/// The library from the backend, kept on the device (a JSON file for the symbols, the image cache
/// for their pictures), so it works offline after the first visit.
@MainActor
@Observable
final class APISymbolCatalog: SymbolCatalog {
    struct Snapshot: Codable, Equatable {
        /// By slug; a symbol opened in full replaces its list entry.
        var symbols: [String: LibrarySymbol] = [:]
        /// Slugs per category, in the server's order.
        var categories: [SymbolCategory: [String]] = [:]
        /// Every slug seen, in first-seen order.
        var order: [String] = []
    }

    private(set) var snapshot: Snapshot

    @ObservationIgnored private let remote: any LibraryRemote
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let images: DreamImageCache
    @ObservationIgnored private let session: URLSession
    /// A category is at most a few pages; this stops a runaway cursor.
    @ObservationIgnored private let maxPages = 10

    init(remote: any LibraryRemote, fileURL: URL? = APISymbolCatalog.defaultFileURL,
         images: DreamImageCache = DreamImageCache(directory: URL.cachesDirectory.appending(path: "SymbolImages", directoryHint: .isDirectory)),
         session: URLSession = .shared) {
        self.remote = remote
        self.fileURL = fileURL
        self.images = images
        self.session = session
        snapshot = fileURL.flatMap { try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: $0)) } ?? Snapshot()
    }

    static var defaultFileURL: URL {
        URL.cachesDirectory.appending(path: "library.json")
    }

    var symbols: [LibrarySymbol] { snapshot.order.compactMap { snapshot.symbols[$0] } }

    func symbols(in category: SymbolCategory) -> [LibrarySymbol] {
        (snapshot.categories[category] ?? []).compactMap { snapshot.symbols[$0] }
    }

    func symbol(id: LibrarySymbol.ID) -> LibrarySymbol? { snapshot.symbols[id] }

    func refresh(category: SymbolCategory) async throws(APIError) {
        var items: [LibrarySymbol] = []
        var cursor: String?
        for _ in 0..<maxPages {
            let page = try await remote.librarySymbols(query: nil, category: category, cursor: cursor, limit: 50)
            items += page.items
            cursor = page.nextCursor
            if cursor == nil { break }
        }
        var next = snapshot
        items.forEach { merge($0, into: &next) }
        next.categories[category] = items.map(\.id)
        commit(next)
    }

    func search(_ query: String) async throws(APIError) -> [LibrarySymbol] {
        let page = try await remote.librarySymbols(query: String(query.prefix(100)), category: nil, cursor: nil, limit: 50)
        var next = snapshot
        page.items.forEach { merge($0, into: &next) }
        commit(next)
        return page.items.map { snapshot.symbols[$0.id] ?? $0 }
    }

    func loadSymbol(id: LibrarySymbol.ID) async throws(APIError) -> LibrarySymbol {
        let symbol = try await remote.librarySymbol(slug: id)
        var next = snapshot
        next.symbols[id] = symbol
        if !next.order.contains(id) { next.order.append(id) }
        commit(next)
        return symbol
    }

    func imageData(for symbol: LibrarySymbol) async -> Data? {
        guard let url = symbol.imageURL else { return nil }
        // Keyed by the link's path: its signature changes, the picture does not.
        let digest = SHA256.hash(data: Data(url.path(percentEncoded: false).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let key = "\(symbol.id)-\(digest)"
        if let cached = await images.data(for: key) { return cached }
        guard let (data, response) = try? await session.data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status), !data.isEmpty else { return nil }
        let prefix = "\(symbol.id)-"
        await images.store(data, for: key) { file in file.hasPrefix(prefix) && !file.hasPrefix(key) }
        return data
    }

    /// A list entry never overwrites the full symbol (lenses, related) opened before.
    private func merge(_ item: LibrarySymbol, into snapshot: inout Snapshot) {
        if var existing = snapshot.symbols[item.id], !existing.lenses.isEmpty {
            existing.title = item.title
            existing.meaning = item.meaning
            existing.categories = item.categories
            existing.imageURL = item.imageURL ?? existing.imageURL
            snapshot.symbols[item.id] = existing
        } else {
            snapshot.symbols[item.id] = item
        }
        if !snapshot.order.contains(item.id) { snapshot.order.append(item.id) }
    }

    private func commit(_ next: Snapshot) {
        guard next != snapshot else { return }
        snapshot = next
        guard let fileURL, let data = try? JSONEncoder().encode(next) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
