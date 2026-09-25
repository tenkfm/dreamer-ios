import Foundation

/// Analysis on the backend: creates the dream (idempotent by the draft's clientId), then follows
/// its progress through the event stream (polling as the fallback) until the interpretation is ready.
/// The main lens is streamed as it is written. Running it again for a dream that failed asks the
/// backend to retry it; leaving the screen only stops listening, the server keeps working.
struct APIDreamAnalysisService: DreamAnalysisService {
    let client: APIClient
    var tracker: DreamProgressTracker

    init(client: APIClient, tracker: DreamProgressTracker? = nil) {
        self.client = client
        self.tracker = tracker ?? DreamProgressTracker(client: client)
    }

    func analyze(_ draft: DreamDraft) -> AsyncThrowingStream<AnalysisProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (dream, _) = try await client.createDream(Self.submission(for: draft))
                    continuation.yield(.accepted(dream.id))
                    var step = dream.analysisStep
                    if dream.status == .failed {
                        // The same clientId after a failure returns the failed dream: queue it again.
                        step = try await client.retryDream(id: dream.id).analysisStep
                    }
                    var reported = 0
                    // analysisStep n = the first n checklist steps are done.
                    func report(upTo step: Int) {
                        while reported < min(step, AnalysisStep.allCases.count) {
                            continuation.yield(.completed(AnalysisStep.allCases[reported]))
                            reported += 1
                        }
                    }

                    if dream.status == .ready {
                        report(upTo: AnalysisStep.allCases.count)
                        continuation.yield(.finished(dream))
                        continuation.finish()
                        return
                    }
                    report(upTo: step)

                    var written = ""
                    for try await event in tracker.events(for: dream.id) {
                        switch event {
                        case .step(let step):
                            report(upTo: step)
                        case .text(_, let delta, let reset):
                            // reset: the backend switched to its fallback provider and starts over.
                            if reset { written = "" }
                            written += delta
                            continuation.yield(.writing(written))
                        case .ready(let ready):
                            report(upTo: AnalysisStep.allCases.count)
                            continuation.yield(.finished(ready))
                        case .failed(let code, let message):
                            throw APIError.server(.init(code: code, message: message, status: 422))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func submission(for draft: DreamDraft) -> DreamSubmission {
        let details: DreamSubmission.Details? = draft.recurrence.map {
            DreamSubmission.Details(emotions: Array(draft.emotions.prefix(5)),
                                    recurrence: $0,
                                    someoneSpecific: draft.someoneSpecific ?? false)
        }
        return DreamSubmission(clientId: draft.clientId, text: draft.transcript, details: details,
                               recordedAt: draft.recordedAt, recordingId: draft.recordingId)
    }
}
