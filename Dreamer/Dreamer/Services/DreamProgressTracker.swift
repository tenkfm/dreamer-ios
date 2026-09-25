import Foundation

/// Follows a dream from "analyzing" to "ready": the live event stream first, then polling
/// `/status` when the stream ends early or the connection drops. A network gap in the middle of
/// the analysis never loses the result - polling keeps trying until the dream is ready or failed,
/// or the caller stops listening (leaving the screen cancels it; the server keeps working).
struct DreamProgressTracker: Sendable {
    let client: APIClient
    /// Polling interval of the fallback (the backend suggests 1-2 s).
    var pollInterval: Duration = .seconds(2)

    func events(for dreamID: UUID) -> AsyncThrowingStream<DreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if try await streamLive(dreamID, into: continuation) {
                        continuation.finish()
                        return
                    }
                    try await poll(dreamID, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// True when the stream delivered the end (ready or failed).
    private func streamLive(_ dreamID: UUID, into continuation: AsyncThrowingStream<DreamEvent, any Error>.Continuation)
    async throws -> Bool {
        do {
            for try await event in client.dreamEventStream(id: dreamID) {
                continuation.yield(event)
                switch event {
                case .ready, .failed: return true
                case .step, .text: continue
                }
            }
            return false
        } catch let error as APIError {
            switch error {
            case .offline, .timeout, .invalidResponse: return false
            case .server(let server) where server.status >= 500: return false
            default: throw error
            }
        }
    }

    private func poll(_ dreamID: UUID, into continuation: AsyncThrowingStream<DreamEvent, any Error>.Continuation)
    async throws {
        var lastStep: Int?
        while !Task.isCancelled {
            do {
                let progress = try await client.dreamProgress(id: dreamID)
                if progress.analysisStep != lastStep {
                    lastStep = progress.analysisStep
                    continuation.yield(.step(progress.analysisStep))
                }
                switch progress.status {
                case .ready:
                    continuation.yield(.ready(try await client.dream(id: dreamID)))
                    return
                case .failed:
                    continuation.yield(.failed(progress.errorCode ?? .dreamFailed, message: ""))
                    return
                case .analyzing:
                    break
                }
            } catch {
                // Offline or a server hiccup: keep waiting for the dream. Anything else is final.
                switch error {
                case .offline, .timeout: break
                case .server(let server) where server.status >= 500: break
                default: throw error
                }
            }
            try await Task.sleep(for: pollInterval)
        }
    }
}
