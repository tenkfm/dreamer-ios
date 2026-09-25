import Foundation
import os
import Testing
@testable import Dreamer

@MainActor
struct DraftQueueTests {
    /// Answers from a script and records every submission.
    final class ScriptedSubmitter: DreamSubmitter {
        private let answers: OSAllocatedUnfairLock<[Result<Void, APIError>]>
        private let sent = OSAllocatedUnfairLock<[String]>(initialState: [])
        init(_ answers: [Result<Void, APIError>]) { self.answers = OSAllocatedUnfairLock(initialState: answers) }
        var clientIds: [String] { sent.withLock { $0 } }

        func submit(_ submission: DreamSubmission) async throws(APIError) -> Dream {
            sent.withLock { $0.append(submission.clientId) }
            let answer = answers.withLock { $0.isEmpty ? .success(()) : $0.removeFirst() }
            if case .failure(let error) = answer { throw error }
            return MockData.analyzedDream(from: DreamDraft(clientId: submission.clientId, transcript: submission.text), at: .now)
        }
    }

    private func makeQueue(_ submitter: ScriptedSubmitter, store: InMemoryDreamStore = InMemoryDreamStore(seed: []),
                           now: @escaping () -> Date = Date.init) throws -> DraftQueue {
        DraftQueue(container: try LocalStore.makeContainer(inMemory: true), submitter: submitter, store: store, now: now)
    }

    private func draft(_ id: String) -> DreamDraft {
        DreamDraft(clientId: id, transcript: "I was flying over a frozen lake", emotions: [.joy], recurrence: .never, someoneSpecific: false)
    }

    @Test func offlineDraftWaitsAndIsSentOnceWhenOnline() async throws {
        let submitter = ScriptedSubmitter([.failure(.offline)])
        let store = InMemoryDreamStore(seed: [])
        let queue = try makeQueue(submitter, store: store)
        queue.save(draft("client-1"))
        #expect(queue.pendingCount == 1)

        await queue.flush()
        #expect(queue.pendingCount == 1)

        await queue.flush()
        #expect(queue.pendingCount == 0)
        #expect(store.dreams.count == 1)

        await queue.flush()
        #expect(submitter.clientIds == ["client-1", "client-1"])
        #expect(store.dreams.count == 1)
    }

    @Test func savingTheSameDreamAgainUpdatesTheDraft() throws {
        let queue = try makeQueue(ScriptedSubmitter([]))
        queue.save(draft("client-1"))
        var edited = draft("client-1")
        edited.transcript = "Corrected text"
        queue.save(edited)

        #expect(queue.pendingCount == 1)
        #expect(queue.pendingDrafts.first?.transcript == "Corrected text")
        #expect(queue.pendingDrafts.first?.emotions == [.joy])
    }

    @Test func dailyLimitWaitsUntilItResets() async throws {
        let reset = Date(timeIntervalSince1970: 2_000_000_000)
        var clock = Date(timeIntervalSince1970: 1_999_990_000)
        let limited = APIError.server(.init(code: .rateLimited, message: "", status: 429, retryAfter: 3600,
                                            limit: "interpretations_per_day", resetAt: reset))
        let submitter = ScriptedSubmitter([.failure(limited)])
        let queue = try makeQueue(submitter) { clock }
        queue.save(draft("client-1"))

        await queue.flush()
        await queue.flush()
        #expect(submitter.clientIds.count == 1)

        clock = reset
        await queue.flush()
        #expect(queue.pendingCount == 0)
    }

    @Test func serverErrorsBackOffPerDraft() async throws {
        let clock = Date(timeIntervalSince1970: 1_000)
        let failure = APIError.server(.init(code: .internalError, message: "", status: 500))
        let submitter = ScriptedSubmitter([.failure(failure), .success(())])
        let queue = try makeQueue(submitter) { clock }
        queue.save(draft("a"))
        queue.save(draft("b"))

        await queue.flush()

        #expect(submitter.clientIds == ["a", "b"])
        #expect(queue.pendingDrafts.map(\.clientId) == ["a"])
    }

    @Test func foregroundAnalysisForgetsTheDraftOnceAccepted() async throws {
        let queue = try makeQueue(ScriptedSubmitter([]))
        let viewModel = AnalysisViewModel(draft: draft("client-9"), service: MockDreamAnalysisService(stepDuration: .zero),
                                          store: InMemoryDreamStore(seed: []), drafts: queue)
        await viewModel.run()

        #expect(viewModel.isFinished)
        #expect(queue.pendingCount == 0)
    }

    @Test func offlineAnalysisKeepsTheDraftAndSaysSo() async throws {
        let queue = try makeQueue(ScriptedSubmitter([]))
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet))
        }
        let viewModel = AnalysisViewModel(draft: draft("client-7"), service: APIDreamAnalysisService(client: client),
                                          store: InMemoryDreamStore(seed: []), drafts: queue)
        await viewModel.run()

        #expect(viewModel.isSavedOffline)
        #expect(viewModel.errorState == nil)
        #expect(queue.pendingDrafts.map(\.clientId) == ["client-7"])
    }

    /// Data Protection exists on devices only; the simulator reports no protection class at all.
    @Test(.enabled(if: !isSimulator)) func storeFileIsCompletelyProtected() throws {
        _ = try LocalStore.makeContainer()
        let directory = URL.applicationSupportDirectory.appending(path: "Dreamer")
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path(percentEncoded: false))
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
    }

    @Test func storeOpensOnDisk() throws {
        let container = try LocalStore.makeContainer()
        #expect(container.configurations.first?.url.lastPathComponent == "Dreamer.store")
    }
}

private var isSimulator: Bool {
    #if targetEnvironment(simulator)
    true
    #else
    false
    #endif
}
