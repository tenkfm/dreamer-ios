import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Supplies and renews the bearer token (implemented by TokenManager).
protocol AccessTokenProvider: Sendable {
    /// A valid access token, refreshed first when it is about to expire. Nil when signed out.
    func accessToken() async throws -> String?
    /// Called when the server rejected `token` as expired; returns a fresh one or throws `.signedOut`.
    func refreshAfterRejection(of token: String) async throws -> String
}

/// The Dreamer API client. Wraps the code generated from `API/openapi.yaml`: the generated types
/// never leave this folder, every method returns domain models from `Models/`.
final class APIClient: Sendable {
    let baseURL: URL
    let client: Client
    /// Plain session for the calls outside the generated client (SSE, uploads, morningInsight).
    let session: URLSession
    let tokens: (any AccessTokenProvider)?

    init(baseURL: URL,
         tokens: (any AccessTokenProvider)?,
         session: URLSession = APIClient.makeSession(),
         extraMiddlewares: [any ClientMiddleware] = []) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
        // Order matters: the first middleware is the outermost. AuthMiddleware must sit outside
        // ErrorMiddleware to see an expired token as a thrown APIError and retry after refresh.
        var middlewares: [any ClientMiddleware] = extraMiddlewares
        if let tokens {
            middlewares.append(AuthMiddleware(tokens: tokens))
        }
        middlewares.append(ErrorMiddleware())
        client = Client(
            serverURL: baseURL,
            configuration: Configuration(dateTranscoder: FlexibleDateTranscoder()),
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: middlewares
        )
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }

    /// Runs a generated call and turns every failure into `APIError`.
    func perform<Output>(_ call: () async throws -> Output) async throws(APIError) -> Output {
        do {
            return try await call()
        } catch {
            throw APIError.unwrap(error) ?? APIError.fromTransport(error)
        }
    }
}

// MARK: - Middlewares

/// Turns any non-2xx response into a thrown `APIError`, so the endpoint wrappers only handle
/// their success cases and every screen sees one error type.
struct ErrorMiddleware: ClientMiddleware {
    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
    async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status.kind != .successful else { return (response, responseBody) }
        let data: Data
        if let responseBody {
            data = (try? await Data(collecting: responseBody, upTo: 64 * 1024)) ?? Data()
        } else {
            data = Data()
        }
        throw APIError.fromResponse(status: response.status.code, body: data,
                                    retryAfterHeader: response.headerFields[.retryAfter])
    }
}

/// Adds the bearer token to private routes and retries once after refreshing an expired one.
struct AuthMiddleware: ClientMiddleware {
    let tokens: any AccessTokenProvider

    /// Operations that work without a session.
    static let publicOperations: Set<String> = [
        "health", "signInWithApple", "requestEmailLink", "verifyEmailLink", "refreshTokens"
    ]

    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
    async throws -> (HTTPResponse, HTTPBody?) {
        guard !Self.publicOperations.contains(operationID) else {
            return try await next(request, body, baseURL)
        }
        guard let token = try await tokens.accessToken() else { throw APIError.signedOut }

        var authorized = request
        authorized.headerFields[.authorization] = "Bearer \(token)"
        do {
            return try await next(authorized, body, baseURL)
        } catch where APIError.unwrap(error)?.code == .authInvalidToken {
            // Bodies built from Data can be sent twice, so the original request is replayed as is.
            let fresh = try await tokens.refreshAfterRejection(of: token)
            authorized.headerFields[.authorization] = "Bearer \(fresh)"
            return try await next(authorized, body, baseURL)
        }
    }
}

// MARK: - Dates

/// The backend writes `2026-09-25T06:12:00.000Z`; older records may lack the fraction.
struct FlexibleDateTranscoder: DateTranscoder {
    func encode(_ date: Date) throws -> String {
        APIDates.format(date)
    }

    func decode(_ string: String) throws -> Date {
        guard let date = APIDates.parse(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not an ISO 8601 date: \(string)"))
        }
        return date
    }
}
