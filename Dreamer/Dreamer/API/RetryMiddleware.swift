import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Retries requests that are safe to send again: GETs, and `POST /v1/dreams`, which the backend
/// deduplicates by `clientId`. Only server errors (5xx) and dropped connections are retried, with
/// exponential backoff; 4xx answers mean the request itself is wrong or not allowed, so they are not.
struct RetryMiddleware: ClientMiddleware {
    var maxAttempts = 3
    /// First delay; doubles on each attempt (0.5 s, 1 s, ...).
    var baseDelay: Duration = .milliseconds(500)

    /// Non-GET operations that are idempotent on the server.
    static let idempotentOperations: Set<String> = ["createDream"]

    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
    async throws -> (HTTPResponse, HTTPBody?) {
        let retryable = request.method == .get || Self.idempotentOperations.contains(operationID)
        var attempt = 1
        while true {
            do {
                return try await next(request, body, baseURL)
            } catch {
                guard retryable, attempt < maxAttempts, Self.shouldRetry(error), !Task.isCancelled else { throw error }
                let delay = baseDelay * (1 << (attempt - 1))
                try await Task.sleep(for: delay)
                attempt += 1
            }
        }
    }

    static func shouldRetry(_ error: any Error) -> Bool {
        switch APIError.unwrap(error) {
        case .server(let server): server.status >= 500 && server.code != .ttsUnavailable
        case .offline, .timeout: true
        default: false
        }
    }
}
