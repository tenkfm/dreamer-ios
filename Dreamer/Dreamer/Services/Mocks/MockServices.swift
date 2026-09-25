import Foundation
import Observation

/// Types the sample transcript in, ~2 characters every 80 ms.
@MainActor
final class MockSpeechService: SpeechService {
    private let text: String
    private let charactersPerTick: Int
    private let tick: Duration
    private var task: Task<Void, Never>?

    init(text: String = MockData.transcript, charactersPerTick: Int = 2, tick: Duration = .milliseconds(80)) {
        self.text = text
        self.charactersPerTick = charactersPerTick
        self.tick = tick
    }

    func start() -> AsyncStream<String> {
        stop()
        let (stream, continuation) = AsyncStream<String>.makeStream()
        task = Task { [text, charactersPerTick, tick] in
            var count = 0
            while count < text.count, !Task.isCancelled {
                try? await Task.sleep(for: tick)
                count = min(text.count, count + charactersPerTick)
                continuation.yield(String(text.prefix(count)))
            }
            continuation.finish()
        }
        return stream
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// Four steps of 1.3 s, then the sample interpretation.
struct MockDreamAnalysisService: DreamAnalysisService {
    var stepDuration: Duration = .milliseconds(1300)

    func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for step in AnalysisStep.allCases {
                        try await Task.sleep(for: stepDuration)
                        continuation.yield(.completed(step))
                    }
                    continuation.yield(.finished(MockData.analyzedDream(from: draft, at: .now)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Always succeeds after a short delay.
struct MockPurchaseService: PurchaseService {
    var delay: Duration = .milliseconds(800)
    var restoredPlan: Plan? = .yearly

    func purchase(_ plan: Plan) async throws {
        try await Task.sleep(for: delay)
    }

    func restore() async throws -> Plan? {
        try await Task.sleep(for: delay)
        return restoredPlan
    }

    func logIn(userID: String) async {}
    func logOut() async {}
}

/// In-memory store seeded with the Journal dreams.
@MainActor
@Observable
final class InMemoryDreamStore: DreamStore {
    private(set) var dreams: [Dream]

    init(seed: [Dream] = MockData.seedDreams()) {
        dreams = seed.sorted { $0.createdAt > $1.createdAt }
    }

    func dream(id: Dream.ID) -> Dream? {
        dreams.first { $0.id == id }
    }

    func save(_ dream: Dream) {
        if let index = dreams.firstIndex(where: { $0.id == dream.id }) {
            dreams[index] = dream
        } else {
            dreams.append(dream)
            dreams.sort { $0.createdAt > $1.createdAt }
        }
    }

    func deleteAll() {
        dreams.removeAll()
    }
}

struct MockSymbolCatalog: SymbolCatalog {
    let symbols = MockData.librarySymbols
}

/// Silent read-out that advances progress on a timer. For previews and tests.
@MainActor
@Observable
final class MockReadAloudService: ReadAloudService {
    private(set) var state: ReadAloudState = .idle
    private(set) var progress: Double = 0
    private(set) var lastText: String?

    func play(_ text: String) {
        if lastText != text { progress = 0 }
        lastText = text
        state = .playing
    }

    func pause() {
        if state == .playing { state = .paused }
    }

    func stop() {
        state = .idle
        progress = 0
        lastText = nil
    }
}

struct MockImageSaver: ImageSaving {
    func saveImage(named assetName: String) async throws {}
}
