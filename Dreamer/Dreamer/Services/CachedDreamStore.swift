import Foundation
import Observation
import SwiftData

/// A journal entry as cached on the device (the summary as JSON, sorted by date).
@Model
final class CachedDreamSummary {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var payload: Data

    init(id: UUID, createdAt: Date, payload: Data) {
        self.id = id
        self.createdAt = createdAt
        self.payload = payload
    }
}

/// A dream in full as cached on the device (text, interpretation, notes: complete file protection
/// through LocalStore).
@Model
final class CachedDream {
    @Attribute(.unique) var id: UUID
    var payload: Data
    var updatedAt: Date

    init(id: UUID, payload: Data, updatedAt: Date) {
        self.id = id
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// What the journal needs from the backend.
protocol DreamRemote: Sendable {
    func listDreams(cursor: String?, limit: Int, emotion: Emotion?, query: String?) async throws(APIError) -> DreamPage
    func dream(id: UUID) async throws(APIError) -> Dream
    func deleteDream(id: UUID) async throws(APIError)
}

extension APIClient: DreamRemote {}

/// The journal on the backend with a SwiftData copy: the cached list shows at once (offline too),
/// then `refresh` brings the server's first page; older pages load as the list scrolls.
@MainActor
@Observable
final class CachedDreamStore: DreamStore {
    private(set) var summaries: [DreamSummary] = []
    private(set) var canLoadMore = false

    /// Full dreams read so far this session (the cache is read on first use).
    private var details: [UUID: Dream] = [:]
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let remote: any DreamRemote
    @ObservationIgnored private let pageSize: Int

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(container: ModelContainer, remote: any DreamRemote, pageSize: Int = 20) {
        self.container = container
        context = container.mainContext
        self.remote = remote
        self.pageSize = pageSize
        let cached = (try? context.fetch(FetchDescriptor<CachedDreamSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        summaries = cached.compactMap { try? Self.decoder.decode(DreamSummary.self, from: $0.payload) }
        // The cursor is not kept: after a relaunch the next page follows a refresh.
        canLoadMore = false
    }

    // MARK: List

    func refresh() async throws(APIError) {
        let page = try await remote.listDreams(cursor: nil, limit: pageSize, emotion: nil, query: nil)
        let fresh = page.items
        // Dreams deleted on another device disappear with their cached text.
        if let oldest = fresh.last?.createdAt {
            let freshIDs = Set(fresh.map(\.id))
            let gone = summaries.filter { $0.createdAt >= oldest && !freshIDs.contains($0.id) }.map(\.id)
            gone.forEach(forgetDetail)
        } else if page.nextCursor == nil {
            summaries.map(\.id).forEach(forgetDetail)
        }
        summaries = fresh
        nextCursor = page.nextCursor
        canLoadMore = page.nextCursor != nil
        replaceCachedSummaries(with: fresh)
    }

    func loadMore() async throws(APIError) {
        guard let cursor = nextCursor else { return }
        let page = try await remote.listDreams(cursor: cursor, limit: pageSize, emotion: nil, query: nil)
        guard cursor == nextCursor else { return }
        let known = Set(summaries.map(\.id))
        let added = page.items.filter { !known.contains($0.id) }
        summaries += added
        nextCursor = page.nextCursor
        canLoadMore = page.nextCursor != nil
        added.forEach(cacheSummary)
        persist()
    }

    // MARK: Dreams

    func dream(id: Dream.ID) -> Dream? {
        if let dream = details[id] { return dream }
        guard let cached = cachedDream(id), let dream = try? Self.decoder.decode(Dream.self, from: cached.payload) else { return nil }
        details[id] = dream
        return dream
    }

    func loadDream(id: Dream.ID) async throws(APIError) -> Dream {
        var dream = try await remote.dream(id: id)
        // Notes typed on this device and not yet confirmed stay (the notes sync sends them).
        if let local = details[id], local.notes != dream.notes, !local.notes.isEmpty, dream.notes.isEmpty {
            dream.notes = local.notes
        }
        save(dream)
        return dream
    }

    func save(_ dream: Dream) {
        details[dream.id] = dream
        if let data = try? Self.encoder.encode(dream) {
            if let cached = cachedDream(dream.id) {
                cached.payload = data
                cached.updatedAt = .now
            } else {
                context.insert(CachedDream(id: dream.id, payload: data, updatedAt: .now))
            }
        }
        var summary = DreamSummary(dream)
        summary.assetName = nil
        if let index = summaries.firstIndex(where: { $0.id == dream.id }) {
            // The list's thumbnail link stays when the dream in full has none.
            summary.thumbnailURL = summary.thumbnailURL ?? summaries[index].thumbnailURL
            summaries[index] = summary
        } else {
            let index = summaries.firstIndex { $0.createdAt < summary.createdAt } ?? summaries.endIndex
            summaries.insert(summary, at: index)
        }
        cacheSummary(summary)
        persist()
    }

    func delete(id: Dream.ID) async throws(APIError) {
        do {
            try await remote.deleteDream(id: id)
        } catch .server(let server) where server.code == .notFound {
            // Already gone (another device): forget it here too.
        }
        summaries.removeAll { $0.id == id }
        forgetDetail(id)
        persist()
    }

    func deleteAll() {
        summaries = []
        details = [:]
        nextCursor = nil
        canLoadMore = false
        try? context.delete(model: CachedDreamSummary.self)
        try? context.delete(model: CachedDream.self)
        persist()
    }

    // MARK: Cache

    private func cachedDream(_ id: UUID) -> CachedDream? {
        var descriptor = FetchDescriptor<CachedDream>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func cachedSummary(_ id: UUID) -> CachedDreamSummary? {
        var descriptor = FetchDescriptor<CachedDreamSummary>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func cacheSummary(_ summary: DreamSummary) {
        guard let data = try? Self.encoder.encode(summary) else { return }
        if let cached = cachedSummary(summary.id) {
            cached.payload = data
            cached.createdAt = summary.createdAt
        } else {
            context.insert(CachedDreamSummary(id: summary.id, createdAt: summary.createdAt, payload: data))
        }
    }

    private func replaceCachedSummaries(with fresh: [DreamSummary]) {
        try? context.delete(model: CachedDreamSummary.self)
        fresh.forEach(cacheSummary)
        persist()
    }

    private func forgetDetail(_ id: UUID) {
        details[id] = nil
        if let cached = cachedDream(id) { context.delete(cached) }
        if let cached = cachedSummary(id) { context.delete(cached) }
    }

    private func persist() {
        try? context.save()
    }
}
