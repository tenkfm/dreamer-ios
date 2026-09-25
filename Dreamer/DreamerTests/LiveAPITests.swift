import Foundation
import Testing
@testable import Dreamer

/// Smoke tests against the staging backend. Off by default (CI stays offline); run with
/// `TEST_RUNNER_DREAMER_LIVE_TESTS=1 xcodebuild test ...`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DREAMER_LIVE_TESTS"] == "1"))
struct LiveAPITests {
    private let staging = URL(string: "https://api-staging-0ea4.up.railway.app")!

    @Test func stagingIsHealthy() async throws {
        let client = APIClient(baseURL: staging, tokens: nil)
        #expect(try await client.health())
    }

    @Test func stagingRejectsAnInvalidTokenWithTheContractShape() async {
        let client = APIClient(baseURL: staging, tokens: RejectedTokens())
        do {
            _ = try await client.profile()
            Issue.record("Expected the invalid token to be rejected")
        } catch {
            // The middleware saw 401 AUTH_INVALID_TOKEN and asked for a refresh, which fails here.
            #expect(error == .signedOut)
        }
    }
}

private struct RejectedTokens: AccessTokenProvider {
    func accessToken() async throws -> String? { "not-a-real-token" }
    func refreshAfterRejection(of token: String) async throws -> String { throw APIError.signedOut }
}
