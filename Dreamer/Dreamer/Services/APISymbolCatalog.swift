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
        /// Where the next page of a category starts; absent when it is complete.
        var nextCursors: [SymbolCategory: String] = [:]
    }

    private(set) var snapshot: Snapshot

    @ObservationIgnored private let remote: any LibraryRemote
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let images: DreamImageCache
    @ObservationIgnored private let session: URLSession
    /// Symbols per page: the first page shows at once, the next ones load as the grid scrolls.
    @ObservationIgnored private let pageSize: Int

    init(remote: any LibraryRemote, fileURL: URL? = APISymbolCatalog.defaultFileURL,
         images: DreamImageCache = DreamImageCache(directory: URL.cachesDirectory.appending(path: "SymbolImages", directoryHint: .isDirectory)),
         session: URLSession = APIClient.mediaSession, pageSize: Int = 20) {
        self.remote = remote
        self.fileURL = fileURL
        self.images = images
        self.session = session
        self.pageSize = pageSize
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

    /// "Popular" is the whole library, most popular first: the server's popular shelf holds only a
    /// handful of the symbols, and the rest would never show. The other chips are their shelves.
    private func remoteCategory(_ category: SymbolCategory) -> SymbolCategory? {
        category == .popular ? nil : category
    }

    /// The first page of a category (again); later pages come with `loadMore`.
    func refresh(category: SymbolCategory) async throws(APIError) {
        let page = try await remote.librarySymbols(query: nil, category: remoteCategory(category), cursor: nil, limit: pageSize)
        var next = snapshot
        page.items.forEach { merge($0, into: &next) }
        let fresh = page.items.map(\.id)
        let current = next.categories[category] ?? []
        // The same first page as before: keep the pages loaded since. Coming back to the Library
        // (or Home refreshing Popular) used to cut the list to 20, and the scroll position jumped.
        if current.count <= fresh.count || Array(current.prefix(fresh.count)) != fresh {
            next.categories[category] = fresh
            next.nextCursors[category] = page.nextCursor
        }
        commit(next)
    }

    func canLoadMore(category: SymbolCategory) -> Bool {
        snapshot.nextCursors[category] != nil
    }

    /// The next page of a category, appended.
    func loadMore(category: SymbolCategory) async throws(APIError) {
        guard let cursor = snapshot.nextCursors[category] else { return }
        let page = try await remote.librarySymbols(query: nil, category: remoteCategory(category), cursor: cursor, limit: pageSize)
        var next = snapshot
        page.items.forEach { merge($0, into: &next) }
        let known = Set(next.categories[category] ?? [])
        next.categories[category, default: []] += page.items.map(\.id).filter { !known.contains($0) }
        next.nextCursors[category] = page.nextCursor
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
