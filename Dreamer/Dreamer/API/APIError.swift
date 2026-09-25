import Foundation
import OpenAPIRuntime

/// Every failure of an API call, as the rest of the app sees it.
/// Backend errors keep the contract's `code` (`{ error: { code, message, details } }`); transport
/// problems are separate cases so screens can tell "offline" from "the server said no".
enum APIError: Error, Equatable, Sendable {
    /// The backend answered with an error body.
    case server(ServerError)
    /// No connection (airplane mode, no route to host, lost connection).
    case offline
    /// The request took too long.
    case timeout
    /// The response did not match the contract (a bug or a stale contract).
    case invalidResponse(status: Int?)
    /// The build has no API host (production domain not configured).
    case notConfigured
    /// The session is gone and the user must sign in again.
    case signedOut

    struct ServerError: Equatable, Sendable {
        var code: APIErrorCode
        var message: String
        var status: Int
        /// From the `Retry-After` header or `details.retryAfterSec`.
        var retryAfter: TimeInterval?
        /// Which daily AI limit was hit (`details.limit`), when a limit applies.
        var limit: String?
        /// When the limit resets (`details.resetAt`, local midnight).
        var resetAt: Date?
    }

    var code: APIErrorCode? {
        if case .server(let error) = self { return error.code }
        return nil
    }
}

/// `ApiErrorCode` of the contract. Codes are never repurposed; an unknown one is handled like
/// `internalError`, as the backend guide asks.
enum APIErrorCode: String, Sendable, CaseIterable, Codable {
    case validationFailed = "VALIDATION_FAILED"
    case authRequired = "AUTH_REQUIRED"
    case authInvalidToken = "AUTH_INVALID_TOKEN"
    case authLinkExpired = "AUTH_LINK_EXPIRED"
    case premiumRequired = "PREMIUM_REQUIRED"
    case rateLimited = "RATE_LIMITED"
    case attestationRequired = "ATTESTATION_REQUIRED"
    case notFound = "NOT_FOUND"
    case conflict = "CONFLICT"
    case dreamFailed = "DREAM_FAILED"
    case ttsUnavailable = "TTS_UNAVAILABLE"
    case providerUnavailable = "PROVIDER_UNAVAILABLE"
    case limitReached = "LIMIT_REACHED"
    case internalError = "INTERNAL_ERROR"

    init(contractValue: String) {
        self = APIErrorCode(rawValue: contractValue) ?? .internalError
    }
}

extension APIError {
    /// Builds the error from a non-2xx response. `body` is the raw JSON the server sent.
    static func fromResponse(status: Int, body: Data, retryAfterHeader: String?) -> APIError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                let code: String
                let message: String
                let details: Details?
            }
            struct Details: Decodable {
                let retryAfterSec: Double?
                let limit: String?
                let resetAt: String?
            }
            let error: Body
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else {
            // Proxies and gateways (502 from the platform, an HTML 404) do not use the contract shape.
            let code: APIErrorCode = status == 404 ? .notFound : (status == 401 ? .authRequired : .internalError)
            return .server(ServerError(code: code, message: "HTTP \(status)", status: status,
                                       retryAfter: retryAfterHeader.flatMap(TimeInterval.init)))
        }
        let details = envelope.error.details
        return .server(ServerError(
            code: APIErrorCode(contractValue: envelope.error.code),
            message: envelope.error.message,
            status: status,
            retryAfter: retryAfterHeader.flatMap(TimeInterval.init) ?? details?.retryAfterSec,
            limit: details?.limit,
            resetAt: details?.resetAt.flatMap(APIDates.parse)
        ))
    }

    /// The APIError inside `error`. OpenAPIRuntime wraps whatever an inner middleware or the
    /// transport throws into ClientError before outer middlewares see it.
    static func unwrap(_ error: any Error) -> APIError? {
        if let api = error as? APIError { return api }
        if let client = error as? ClientError {
            if let api = client.underlyingError as? APIError { return api }
            return fromTransport(client.underlyingError)
        }
        return nil
    }

    /// Maps URLSession failures to the transport cases.
    static func fromTransport(_ error: any Error) -> APIError {
        if let api = error as? APIError { return api }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
                return .offline
            default: return .offline
            }
        }
        return .invalidResponse(status: nil)
    }
}

/// ISO 8601 as the backend writes it (`2026-09-25T06:12:00.000Z`), with or without fractions.
enum APIDates {
    static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: fractional) { return date }
        return try? Date(string, strategy: plain)
    }

    static func format(_ date: Date) -> String {
        date.formatted(fractional)
    }

    /// `YYYY-MM-DD` (week starts, `weekOf`) as a date at UTC midnight.
    static func parseDay(_ string: String) -> Date? {
        try? Date(string, strategy: Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash))
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()
}
