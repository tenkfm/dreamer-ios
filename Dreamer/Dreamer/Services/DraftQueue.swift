import Foundation
import Observation
import SwiftData

/// A told dream waiting to reach the backend. Stored with SwiftData under complete file protection
/// (the file is unreadable while the phone is locked); the dream text never leaves this store
/// except in the POST that creates the dream.
@Model
final class DraftRecord {
    /// The idempotency key of `POST /v1/dreams`: resending returns the same dream.
    @Attribute(.unique) var clientId: String
    var text: String
    var emotions: [String]
    var recurrence: Int?
    var someoneSpecific: Bool?
    var recordedAt: Date?
    var recordingId: String?
    var createdAt: Date
    var attempts: Int
    /// Not before this (rate limit, backoff).
    var nextAttemptAt: Date?
    /// Why the last attempt failed (an API error code), for the Home status.
    var lastErrorCode: String?

    init(draft: DreamDraft, now: Date = .now) {
        clientId = draft.clientId
        text = draft.transcript
        emotions = draft.emotions.map(\.rawValue)
        recurrence = draft.recurrence?.rawValue
        someoneSpecific = draft.someoneSpecific
        recordedAt = draft.recordedAt
        recordingId = draft.recordingId
        createdAt = now
        attempts = 0
    }

    var draft: DreamDraft {
        DreamDraft(clientId: clientId, transcript: text, emotions: emotions.compactMap(Emotion.init(rawValue:)),
                   recurrence: recurrence.flatMap(Recurrence.init(rawValue:)), someoneSpecific: someoneSpecific,
                   recordedAt: recordedAt, recordingId: recordingId)
    }
}

/// Creates a dream on the backend. Idempotent by `clientId`.
protocol DreamSubmitter: Sendable {
    func submit(_ submission: DreamSubmission) async throws(APIError) -> Dream
}

extension APIClient: DreamSubmitter {
    func submit(_ submission: DreamSubmission) async throws(APIError) -> Dream {
        try await createDream(submission).dream
    }
}

/// Drafts that still have to be sent, and the sending. Every told dream is saved here first, so a
/// dropped connection, a crash or a relaunch never loses it; `flush` sends what is waiting when the
/// network is back, at launch and after sign-in.
@MainActor
@Observable
final class DraftQueue {
    private(set) var pendingCount = 0
    private(set) var isSending = false

    /// Kept alive here: a ModelContext does not retain its container.
    private let container: ModelContainer
    private let context: ModelContext
    private let submitter: any DreamSubmitter
    private let store: any DreamStore
    private let now: () -> Date

    init(container: ModelContainer, submitter: any DreamSubmitter, store: any DreamStore, now: @escaping () -> Date = Date.init) {
        self.container = container
        context = container.mainContext
        self.submitter = submitter
        self.store = store
        self.now = now
        refreshCount()
    }

    /// Keeps a draft until the backend has it (same clientId = the same draft, updated).
    func save(_ draft: DreamDraft) {
        if let existing = record(clientId: draft.clientId) {
            existing.text = draft.transcript
            existing.emotions = draft.emotions.map(\.rawValue)
            existing.recurrence = draft.recurrence?.rawValue
            existing.someoneSpecific = draft.someoneSpecific
            existing.recordingId = draft.recordingId
        } else {
            context.insert(DraftRecord(draft: draft, now: now()))
        }
        persist()
    }

    /// A told dream that has not been read yet (offline, no plan, a failure), for Journal and Home.
    struct Pending: Identifiable, Hashable {
        var draft: DreamDraft
        var createdAt: Date
        var id: String { draft.clientId }
    }

    /// Newest first. Reads `pendingCount`, so views showing it update as drafts come and go.
    var pending: [Pending] {
        _ = pendingCount
        return records().map { Pending(draft: $0.draft, createdAt: $0.draft.recordedAt ?? $0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The user deleted a dream that was never read.
    func discard(clientId: String) {
        markSent(clientId: clientId)
    }

    /// The backend accepted the draft (by the foreground analysis or by `flush`).
    func markSent(clientId: String) {
        guard let record = record(clientId: clientId) else { return }
        context.delete(record)
        persist()
    }

    var pendingDrafts: [DreamDraft] { records().map(\.draft) }

    /// Sends every draft that is due. Stops at the first sign that sending is pointless now
    /// (offline, signed out, paywall, daily limit); other failures back off per draft.
    func flush() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false; refreshCount() }

        for record in records() where (record.nextAttemptAt ?? .distantPast) <= now() {
            let clientId = record.clientId
            record.attempts += 1
            do {
                let dream = try await submitter.submit(APIDreamAnalysisService.submission(for: record.draft))
                store.save(dream)
                markSent(clientId: clientId)
            } catch {
                record.lastErrorCode = error.code?.rawValue ?? String(describing: error)
                switch error {
                case .offline, .timeout, .signedOut, .notConfigured:
                    persist()
                    return
                case .server(let server) where server.code == .premiumRequired:
                    persist()
                    return
                case .server(let server) where server.code == .rateLimited || server.code == .limitReached:
                    record.nextAttemptAt = server.resetAt ?? server.retryAfter.map { now().addingTimeInterval($0) }
                    persist()
                    return
                case .server(let server) where server.code == .validationFailed:
                    // The text can never be accepted as is (too short, too long): keep it, stop retrying.
                    record.nextAttemptAt = .distantFuture
                default:
                    // Exponential backoff: 30 s, 1 min, 2 min... capped at an hour.
                    let delay = min(3600, 30 * pow(2, Double(max(0, record.attempts - 1))))
                    record.nextAttemptAt = now().addingTimeInterval(delay)
                }
                persist()
            }
        }
    }

    /// Account deletion and sign-out.
    func removeAll() {
        for record in records() { context.delete(record) }
        persist()
    }

    private func records() -> [DraftRecord] {
        let descriptor = FetchDescriptor<DraftRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func record(clientId: String) -> DraftRecord? {
        var descriptor = FetchDescriptor<DraftRecord>(predicate: #Predicate { $0.clientId == clientId })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func persist() {
        try? context.save()
        refreshCount()
    }

    private func refreshCount() {
        pendingCount = (try? context.fetchCount(FetchDescriptor<DraftRecord>())) ?? 0
    }
}

/// The app's SwiftData container: in Application Support, protected until first unlock would let a
/// locked phone sync, but the text of dreams asks for more - complete protection.
enum LocalStore {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([DraftRecord.self, CachedDreamSummary.self, CachedDream.self])
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let directory = URL.applicationSupportDirectory.appending(path: "Dreamer", directoryHint: .isDirectory)
        // Files created in a protected directory inherit its protection class.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        // path(percentEncoded: false): "Application Support" must keep its space to be found.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: directory.path(percentEncoded: false))
        let configuration = ModelConfiguration(url: directory.appending(path: "Dreamer.store"))
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
