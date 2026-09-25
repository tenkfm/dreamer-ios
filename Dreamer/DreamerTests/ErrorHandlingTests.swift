import Foundation
import os
import Testing
@testable import Dreamer

struct ErrorStateTests {
    private func server(_ code: APIErrorCode, status: Int = 400, retryAfter: TimeInterval? = nil,
                        limit: String? = nil, resetAt: Date? = nil) -> APIError {
        .server(.init(code: code, message: "", status: status, retryAfter: retryAfter, limit: limit, resetAt: resetAt))
    }

    @Test func everyCodeHasItsOwnState() {
        let kinds = APIErrorCode.allCases.map { ErrorState(server($0)).kind }
        #expect(kinds.count == APIErrorCode.allCases.count)
        #expect(ErrorState(server(.premiumRequired, status: 402)).action == .openPaywall)
        #expect(ErrorState(server(.authLinkExpired, status: 401)).action == .requestNewLink)
        #expect(ErrorState(server(.authRequired, status: 401)).action == .signIn)
        #expect(ErrorState(server(.dreamFailed, status: 422)).kind == .dreamFailed)
        #expect(ErrorState(server(.ttsUnavailable, status: 503)).kind == .voiceUnavailable)
        #expect(ErrorState(server(.notFound, status: 404)).action == .dismiss)
    }

    @Test func transportFailuresHaveStates() {
        #expect(ErrorState(.offline).kind == .offline)
        #expect(ErrorState(.timeout).kind == .timeout)
        #expect(ErrorState(.signedOut).action == .signIn)
        #expect(ErrorState(.invalidResponse(status: 200)).kind == .outdatedApp)
    }

    @Test func dailyLimitSaysWhenToComeBack() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 22)))
        let reset = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26)))
        let state = ErrorState(server(.rateLimited, status: 429, retryAfter: 7200, limit: "interpretations_per_day", resetAt: reset),
                               now: now, calendar: calendar)

        #expect(state.kind == .rateLimited)
        #expect(state.retryAfter == reset)
        #expect(state.message.hasPrefix("You’ve reached today’s limit. Come back after tomorrow at"))
        #expect(state.actionTitle == nil)
    }
}

struct RetryTests {
    final class Counter: Sendable {
        private let value = OSAllocatedUnfairLock(initialState: 0)
        func next() -> Int { value.withLock { $0 += 1; return $0 } }
        var count: Int { value.withLock { $0 } }
    }

    @Test func getIsRetriedAfterServerErrors() async throws {
        let calls = Counter()
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            calls.next() < 3
                ? .json(503, #"{"error":{"code":"PROVIDER_UNAVAILABLE","message":"down"}}"#)
                : .json(200, #"{"days":[],"count":2}"#)
        }
        #expect(try await client.weekInsight().count == 2)
        #expect(calls.count == 3)
    }

    @Test func createDreamIsRetriedAfterADroppedConnection() async throws {
        let calls = Counter()
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            calls.next() == 1
                ? .init(status: 0, body: Data(), error: URLError(.networkConnectionLost))
                : .json(201, APIClientTests.dreamJSON)
        }
        let result = try await client.createDream(DreamSubmission(clientId: "client-123", text: "A dream", details: nil,
                                                                  recordedAt: nil, recordingId: nil))
        #expect(result.created)
        #expect(calls.count == 2)
    }

    @Test func nonIdempotentPostIsNotRetried() async {
        let calls = Counter()
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            _ = calls.next()
            return .json(503, #"{"error":{"code":"PROVIDER_UNAVAILABLE","message":"down"}}"#)
        }
        await #expect(throws: APIError.self) { _ = try await client.regenerateImage(id: UUID()) }
        #expect(calls.count == 1)
    }

    @Test func clientErrorsAreNotRetried() async {
        let calls = Counter()
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            _ = calls.next()
            return .json(429, #"{"error":{"code":"RATE_LIMITED","message":"slow down","details":{"retryAfterSec":30}}}"#,
                         headers: ["Retry-After": "30"])
        }
        await #expect(throws: APIError.self) { _ = try await client.weekInsight() }
        #expect(calls.count == 1)
    }
}
