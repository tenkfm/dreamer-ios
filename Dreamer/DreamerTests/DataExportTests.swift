import Foundation
import os
import Testing
@testable import Dreamer

struct DataExportClientTests {
    /// The bytes are the server's: a field this build does not know and the server's key order stay.
    @Test func theExportIsTheServersBytes() async throws {
        let body = Data(#"{"format":"dreamer-export-v1","zeta":1,"alpha":{"unknownField":true},"dreams":[]}"#.utf8)
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 200, headers: ["Content-Type": "application/json", "Cache-Control": "no-store"], body: body)
        }
        #expect(try await client.exportData() == body)
        #expect(StubURLProtocol.requests(for: host).first?.url?.path() == "/v1/me/export")
    }

    @Test func theHourlyLimitIsRateLimited() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(429, #"{"error":{"code":"RATE_LIMITED","message":"x","details":{"retryAfterSec":1800}}}"#)
        }
        await #expect(throws: APIError.self) { try await client.exportData() }
        do {
            _ = try await client.exportData()
        } catch {
            #expect(error.code == .rateLimited)
        }
    }
}

/// Answers the export from a script, after `delay`; counts the calls.
final class ScriptedExport: DataExporting, @unchecked Sendable {
    private let result: Result<Data, APIError>
    private let delay: Duration
    private let count = OSAllocatedUnfairLock(initialState: 0)
    var calls: Int { count.withLock { $0 } }

    init(_ result: Result<Data, APIError>, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func exportData() async throws(APIError) -> Data {
        count.withLock { $0 += 1 }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return try result.get()
    }
}

@MainActor
struct DataExportSettingsTests {
    private static let body = Data(#"{"format":"dreamer-export-v1","dreams":[{"title":"Stairs"}]}"#.utf8)

    private func make(_ export: ScriptedExport) -> SettingsViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        // 23:30 UTC on 2 October is already 3 October in Warsaw: the name follows the local date.
        let now = Date(timeIntervalSince1970: 1_790_983_800)
        return SettingsViewModel(appState: AppState(store: InMemoryPreferencesStore()), purchases: MockPurchaseService(),
                                 account: MockAccountActions(), dataExport: export, calendar: calendar, now: { now })
    }

    @Test func theFileHoldsTheExactBytesAndGoesAwayWithTheSheet() async throws {
        let viewModel = make(ScriptedExport(.success(Self.body)))
        await viewModel.exportData()

        let file = try #require(viewModel.exportFile?.url)
        #expect(file.lastPathComponent == "mooncatch-export-2026-10-03.json")
        #expect(try Data(contentsOf: file) == Self.body)
        #expect(!viewModel.isExporting)

        viewModel.exportShared(completed: true)
        #expect(viewModel.haptic?.kind == .success)
        viewModel.exportSheetDismissed()
        #expect(!FileManager.default.fileExists(atPath: file.path()))
        #expect(viewModel.exportFile == nil)
    }

    @Test func aCancelledShareStillDeletesTheFile() async throws {
        let viewModel = make(ScriptedExport(.success(Self.body)))
        await viewModel.exportData()
        let file = try #require(viewModel.exportFile?.url)
        viewModel.exportShared(completed: false)
        viewModel.exportSheetDismissed()
        #expect(!FileManager.default.fileExists(atPath: file.path()))
    }

    @Test func tapsWhileExportingAreIgnored() async {
        let export = ScriptedExport(.success(Self.body), delay: .milliseconds(80))
        let viewModel = make(export)
        async let first: Void = viewModel.exportData()
        try? await Task.sleep(for: .milliseconds(10))
        #expect(viewModel.isExporting)
        await viewModel.exportData()
        await first
        #expect(export.calls == 1)
        viewModel.exportSheetDismissed()
    }

    @Test func theHourlyLimitIsExplained() async {
        let viewModel = make(ScriptedExport(.failure(.server(.init(code: .rateLimited, message: "", status: 429, retryAfter: 1800)))))
        await viewModel.exportData()
        #expect(viewModel.alertMessage == "You can export your data 3 times an hour. Try again later.")
        #expect(viewModel.exportFile == nil)
        #expect(viewModel.haptic?.kind == .error)
    }

    @Test func noNetworkOrAnyOtherFailureSaysSo() async {
        for error in [APIError.offline, .timeout, .server(.init(code: .internalError, message: "", status: 500))] {
            let viewModel = make(ScriptedExport(.failure(error)))
            await viewModel.exportData()
            #expect(viewModel.alertMessage == "Couldn’t export your data. Check your connection and try again.")
        }
    }

    /// A session that could not be refreshed sends the app to sign-in; no alert on top of it.
    @Test func anEndedSessionShowsNoAlert() async {
        let viewModel = make(ScriptedExport(.failure(.signedOut)))
        await viewModel.exportData()
        #expect(viewModel.alertMessage == nil)
    }
}
