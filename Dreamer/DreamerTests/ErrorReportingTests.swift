import Foundation
import os
import Testing
@testable import Dreamer

final class RecordingCrashReporter: CrashReporter, @unchecked Sendable {
    struct Report: Equatable {
        var description: String
        var code: String?
        var context: [String: String]
    }

    private let reports = OSAllocatedUnfairLock<[Report]>(initialState: [])
    var all: [Report] { reports.withLock { $0 } }

    func recordNonFatal(_ error: any Error, code: String?, context: [String: String]) {
        let report = Report(description: error.localizedDescription, code: code, context: context)
        reports.withLock { $0.append(report) }
    }

    func setUserID(_ id: String?) {}
}

struct ErrorReportingTests {
    private func client(_ reporter: RecordingCrashReporter, answer: @escaping StubURLProtocol.Handler) -> APIClient {
        StubURLProtocol.makeClient(tokens: StaticTokens(), middlewares: [ErrorReportingMiddleware(reporter: reporter)],
                                   reporter: reporter, handler: answer).0
    }

    @Test func anOutageIsReportedOnceAfterTheRetries() async {
        let reporter = RecordingCrashReporter()
        let api = client(reporter) { _ in .json(503, #"{"error":{"code":"PROVIDER_UNAVAILABLE","message":"down"}}"#) }
        _ = try? await api.dream(id: UUID())

        #expect(reporter.all == [.init(description: "API getDream failed: PROVIDER_UNAVAILABLE", code: "PROVIDER_UNAVAILABLE",
                                       context: ["operation": "getDream"])])
    }

    @Test(arguments: [
        #"{"error":{"code":"PREMIUM_REQUIRED","message":"x"}}"#,
        #"{"error":{"code":"RATE_LIMITED","message":"x"}}"#,
        #"{"error":{"code":"NOT_FOUND","message":"x"}}"#
    ])
    func expectedAnswersAreNotReported(body: String) async {
        let reporter = RecordingCrashReporter()
        let status = body.contains("PREMIUM") ? 402 : body.contains("RATE") ? 429 : 404
        let api = client(reporter) { _ in .json(status, body) }
        _ = try? await api.dream(id: UUID())
        #expect(reporter.all.isEmpty)
    }

    @Test func beingOfflineIsNotABug() async {
        let reporter = RecordingCrashReporter()
        let api = client(reporter) { _ in .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet)) }
        _ = try? await api.weekInsight()
        #expect(reporter.all.isEmpty)
    }

    @Test func anUnreadableAnswerIsReported() async {
        let reporter = RecordingCrashReporter()
        let api = client(reporter) { _ in .json(200, #"{"unexpected":true}"#) }
        _ = try? await api.weekInsight()
        #expect(reporter.all.map(\.context) == [["operation": "weekInsight"]])
    }

    @Test func aReportNeverCarriesTheQuery() async {
        let reporter = RecordingCrashReporter()
        let api = client(reporter) { _ in .json(500, #"{"error":{"code":"INTERNAL_ERROR","message":"boom"}}"#) }
        _ = try? await api.listDreams(query: "my secret dream")
        let report = try? #require(reporter.all.first)
        #expect(report?.description.contains("secret") == false)
        #expect(report?.context.values.contains { $0.contains("secret") } == false)
    }
}
