import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Reports API failures that point to a bug or an outage as non-fatal errors, after retries, grouped
/// by operation and error code. Expected answers (offline, signed out, paywall, limits, not found)
/// are the product working as designed and are not reported. Only the operation id and the code
/// leave the device: never the URL (search queries), the body or a header.
struct ErrorReportingMiddleware: ClientMiddleware {
    let reporter: any CrashReporter

    /// A failure worth a report: 5xx, unreadable responses, and requests the server refused as
    /// malformed or unverified (a client bug or an attestation problem).
    static func isReportable(_ error: APIError) -> Bool {
        switch error {
        // Unreadable bodies are reported by APIClient, which knows the endpoint; here only a
        // non-JSON error answer (a proxy page) arrives as invalidResponse.
        case .invalidResponse: true
        case .server(let server):
            server.status >= 500 || [.validationFailed, .attestationRequired, .conflict].contains(server.code)
        case .offline, .timeout, .signedOut, .notConfigured: false
        }
    }

    static func code(of error: APIError) -> String {
        switch error {
        case .server(let server): server.code.rawValue
        case .invalidResponse(let status): "INVALID_RESPONSE_\(status.map(String.init) ?? "DECODING")"
        case .offline: "OFFLINE"
        case .timeout: "TIMEOUT"
        case .signedOut: "SIGNED_OUT"
        case .notConfigured: "NOT_CONFIGURED"
        }
    }

    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
    async throws -> (HTTPResponse, HTTPBody?) {
        do {
            return try await next(request, body, baseURL)
        } catch {
            if let apiError = APIError.unwrap(error), Self.isReportable(apiError) {
                let code = Self.code(of: apiError)
                reporter.recordNonFatal(APIFailure(operation: operationID, code: code), code: code,
                                        context: ["operation": operationID])
            }
            throw error
        }
    }
}

/// What a report says about a failed call: which operation, which code. Nothing else.
struct APIFailure: LocalizedError, Equatable {
    let operation: String
    let code: String

    var errorDescription: String? { "API \(operation) failed: \(code)" }
}
