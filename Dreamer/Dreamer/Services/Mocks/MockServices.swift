import Foundation
import Observation
import os

/// Types the sample transcript in, ~2 characters every 80 ms, with a talking-like level.
@MainActor
final class MockSpeechService: SpeechService {
    private let text: String
    private let charactersPerTick: Int
    private let tick: Duration
    /// Off: no words while talking, only audio for the server fallback (IOS-04.5).
    private let liveText: Bool
    private var task: Task<Void, Never>?
    private var recordedTicks = 0

    init(text: String = MockData.transcript, charactersPerTick: Int = 2, tick: Duration = .milliseconds(80),
         liveText: Bool = true) {
        self.text = text
        self.charactersPerTick = liveText ? charactersPerTick : 0
        self.tick = tick
        self.liveText = liveText
    }

    var keepsAudio: Bool { !liveText }

    func start() -> AsyncThrowingStream<SpeechEvent, any Error> {
        stop()
        let (stream, continuation) = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        if !liveText { continuation.yield(.liveTextUnavailable) }
        task = Task { [weak self, text, charactersPerTick, tick] in
            var count = 0
            var phase = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                phase += 0.9
                continuation.yield(.level(Float(0.35 + 0.3 * sin(phase) + 0.2 * sin(phase * 2.7))))
                self?.recordedTicks += 1
                if charactersPerTick > 0, count < text.count {
                    count = min(text.count, count + charactersPerTick)
                    continuation.yield(.transcript(String(text.prefix(count))))
                }
            }
            continuation.finish()
        }
        return stream
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// A small placeholder file standing for the audio.
    func takeRecording() -> RecordedAudio? {
        stop()
        guard keepsAudio, recordedTicks > 0, let url = try? RecordingFiles.newFileURL(),
              (try? Data(count: 1024).write(to: url)) != nil else { return nil }
        let tickSeconds = Double(tick.components.seconds) + Double(tick.components.attoseconds) / 1e18
        let duration = Double(recordedTicks) * tickSeconds
        recordedTicks = 0
        return RecordedAudio(url: url, duration: duration)
    }

    func discardRecording() {
        stop()
        recordedTicks = 0
    }
}

/// Writes every recording down as the sample dream after a short wait.
struct MockRecordingTranscriber: RecordingTranscriber {
    var text = MockData.transcript
    var delay: Duration = .milliseconds(1500)

    func upload(_ audio: RecordedAudio) async throws(APIError) -> String {
        try? await Task.sleep(for: delay / 2)
        audio.delete()
        return "rec_mock_\(UUID().uuidString.prefix(8).lowercased())"
    }

    func transcribe(recordingID: String) async throws(APIError) -> String {
        try? await Task.sleep(for: delay / 2)
        return text
    }
}

/// Four steps of 1.3 s, then the sample interpretation.
struct MockDreamAnalysisService: DreamAnalysisService {
    var stepDuration: Duration = .milliseconds(1300)
    /// The backend refusing the dream (e.g. PREMIUM_REQUIRED), to see that state.
    var failure: APIError?

    func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let failure {
                        try await Task.sleep(for: stepDuration)
                        throw failure
                    }
                    continuation.yield(.accepted(UUID()))
                    let dream = MockData.analyzedDream(from: draft, at: .now)
                    for step in AnalysisStep.allCases {
                        if step == .writing, stepDuration > .zero {
                            // The main lens arrives word by word, as the backend streams it.
                            let words = (dream.interpretation?.text(for: dream.mainLens ?? .psychology) ?? "").split(separator: " ")
                            for count in stride(from: 3, through: words.count, by: 3) {
                                try await Task.sleep(for: stepDuration / 12)
                                continuation.yield(.writing(words.prefix(count).joined(separator: " ")))
                            }
                        } else {
                            try await Task.sleep(for: stepDuration)
                        }
                        continuation.yield(.completed(step))
                    }
                    continuation.yield(.finished(dream))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Always succeeds after a short delay, with the design's US prices.
struct MockPurchaseService: PurchaseService {
    var delay: Duration = .milliseconds(800)
    var restoredPlan: Plan? = .yearly
    /// The user already used the yearly trial.
    var trialEligible = true

    func products() async throws -> [PaywallProduct] {
        [
            PaywallProduct(plan: .yearly, productID: Plan.yearly.productID, displayPrice: "$39.99", price: 39.99,
                           currencyCode: "USD", period: .init(value: 1, unit: .year), displayPricePerMonth: "$3.33",
                           trial: trialEligible ? .init(period: .init(value: 1, unit: .week)) : nil),
            PaywallProduct(plan: .weekly, productID: Plan.weekly.productID, displayPrice: "$6.99", price: 6.99,
                           currencyCode: "USD", period: .init(value: 1, unit: .week), displayPricePerMonth: nil, trial: nil)
        ]
    }

    func purchase(_ plan: Plan) async throws -> PurchaseOutcome {
        try await Task.sleep(for: delay)
        return .purchased(EntitlementState(isPremium: true, plan: plan, expiresAt: nil, willRenew: true))
    }

    func restore() async throws -> EntitlementState {
        try await Task.sleep(for: delay)
        guard let restoredPlan else { return .none }
        return EntitlementState(isPremium: true, plan: restoredPlan, expiresAt: nil, willRenew: true)
    }

    func entitlementUpdates() -> AsyncStream<EntitlementState> {
        // Mock access lives in AppState (preferences); nothing changes behind the app's back.
        AsyncStream { $0.finish() }
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

    var summaries: [DreamSummary] { dreams.map { DreamSummary($0) } }
    let canLoadMore = false

    func refresh() async throws(APIError) {}
    func loadMore() async throws(APIError) {}

    func dream(id: Dream.ID) -> Dream? {
        dreams.first { $0.id == id }
    }

    func loadDream(id: Dream.ID) async throws(APIError) -> Dream {
        guard let dream = dream(id: id) else { throw APIError.server(.init(code: .notFound, message: "", status: 404)) }
        return dream
    }

    func delete(id: Dream.ID) async throws(APIError) {
        dreams.removeAll { $0.id == id }
    }

    /// Like the backend: text, title and interpretation, with the matching sentence as the snippet.
    func search(query: String?, emotion: Emotion?) async throws(APIError) -> [DreamSummary] {
        dreams.compactMap { dream in
            if let emotion, !dream.emotions.contains(emotion) { return nil }
            var summary = DreamSummary(dream)
            guard let query, !query.isEmpty else { return summary }
            let texts = [dream.title, dream.transcript] + Lens.allCases.map { dream.interpretation?.text(for: $0) ?? "" }
            guard let text = texts.first(where: { $0.localizedCaseInsensitiveContains(query) }) else { return nil }
            summary.snippet = text.split(separator: ".").first { $0.localizedCaseInsensitiveContains(query) }
                .map { sentence in
                    // Matched words in ** like the backend's snippet.
                    let marked = sentence.replacingOccurrences(of: query, with: "**\(query)**", options: .caseInsensitive)
                    return marked.trimmingCharacters(in: .whitespaces) + "."
                }
            return summary
        }
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

/// Accepts every draft as the sample dream.
struct MockDreamSubmitter: DreamSubmitter {
    /// The same refusal as the mock analysis (`-premiumRequired`), so a waiting draft stays waiting.
    var failure: APIError?

    func submit(_ submission: DreamSubmission) async throws(APIError) -> Dream {
        if let failure { throw failure }
        var draft = DreamDraft(clientId: submission.clientId, transcript: submission.text)
        draft.emotions = submission.details?.emotions ?? []
        return MockData.analyzedDream(from: draft, at: submission.recordedAt ?? .now)
    }
}

@MainActor
final class MockSymbolCatalog: SymbolCatalog {
    let symbols = MockData.librarySymbols

    func symbols(in category: SymbolCategory) -> [LibrarySymbol] {
        symbols.filter { $0.categories.contains(category) }
    }

    func symbol(id: LibrarySymbol.ID) -> LibrarySymbol? { symbols.first { $0.id == id } }

    func refresh(category: SymbolCategory) async throws(APIError) {}
    func canLoadMore(category: SymbolCategory) -> Bool { false }
    func loadMore(category: SymbolCategory) async throws(APIError) {}

    func search(_ query: String) async throws(APIError) -> [LibrarySymbol] {
        symbols.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.meaning.localizedCaseInsensitiveContains(query) }
    }

    func loadSymbol(id: LibrarySymbol.ID) async throws(APIError) -> LibrarySymbol {
        guard let symbol = symbol(id: id) else { throw APIError.server(.init(code: .notFound, message: "", status: 404)) }
        return symbol
    }

    func imageData(for symbol: LibrarySymbol) async -> Data? { nil }
}

/// Silent read-out that advances progress on a timer. For previews and tests.
@MainActor
@Observable
final class MockReadAloudService: ReadAloudService {
    private(set) var state: ReadAloudState = .idle
    private(set) var progress: Double = 0
    private(set) var lastText: String?
    private(set) var lastItem: ReadAloudItem?
    var onFinish: (@MainActor () -> Void)?

    func play(_ item: ReadAloudItem) {
        if lastText != item.text { progress = 0 }
        lastText = item.text
        lastItem = item
        state = .playing
    }

    /// Tests: the read-out reached its end.
    func finish() {
        state = .idle
        progress = 1
        onFinish?()
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
    func saveImage(data: Data) async throws {}
}

/// "Paints" one dream's image: pending on the first look, ready on the next, served from the
/// asset catalog. For the debug screen and tests of the generating state.
final class MockDreamImageService: DreamImageLoading, DreamImageActions, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<Dream>

    init(dream: Dream) {
        state = OSAllocatedUnfairLock(initialState: dream)
    }

    func refreshDream(id: UUID) async throws(APIError) -> Dream {
        state.withLock { dream in
            if let image = dream.image, image.status == .pending {
                dream.image = DreamImageInfo(status: .ready, url: URL(string: "https://media.mock/\(id).jpg"),
                                             width: 1024, height: 1536, version: image.version)
            }
            return dream
        }
    }

    func regenerateImage(id: UUID) async throws(APIError) -> Dream {
        state.withLock { dream in
            dream.image = DreamImageInfo(status: .pending, version: (dream.image?.version ?? 0) + 1)
            return dream
        }
    }

    func imageData(dreamID: UUID, image: DreamImageInfo, size: DreamImageSize) async throws(APIError) -> Data {
        let name = state.withLock { $0.imageName }
        guard let data = DreamImage.uiImage(named: name)?.jpegData(compressionQuality: 0.9) else {
            throw APIError.invalidResponse(status: nil)
        }
        return data
    }

    func thumbnailData(dreamID: UUID, url: URL) async throws(APIError) -> Data {
        try await imageData(dreamID: dreamID, image: DreamImageInfo(status: .ready, version: 1), size: .thumbnail)
    }

    func removeAll() async {}
}
