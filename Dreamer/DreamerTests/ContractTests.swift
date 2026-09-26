import Foundation
import Testing
@testable import Dreamer

/// The response examples of the OpenAPI contract (scripts/extract_openapi_examples.py), keyed by
/// operation id and status.
enum ContractExamples {
    nonisolated(unsafe) static let all: [String: [String: Any]] = {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/openapi-examples.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        return json
    }()

    static func body(_ operation: String, _ status: Int) -> Data? {
        guard let example = all[operation]?[String(status)] else { return nil }
        return try? JSONSerialization.data(withJSONObject: example)
    }

    /// A client whose every answer is the example of `operation` with `status`.
    static func client(_ operation: String, status: Int) -> APIClient {
        let body = self.body(operation, status) ?? Data()
        return StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: status, headers: ["Content-Type": "application/json"], body: body)
        }.0
    }
}

/// Every success example of the contract goes through the app's mapping: a renamed field, a new
/// required value or a changed enum fails here instead of on a user's phone.
struct ContractSuccessTests {
    private let id = UUID(uuidString: "0B6F3C55-1D3C-4B8E-9F1E-2C7A8E5D4F10")!

    @Test func theFixtureIsThere() {
        #expect(ContractExamples.all.count > 30)
    }

    @Test func account() async throws {
        let profile = try await ContractExamples.client("getProfile", status: 200).profile()
        #expect(!profile.id.isEmpty)
        _ = try await ContractExamples.client("updateProfile", status: 200).updateProfile(ProfileUpdate(preferredLens: .spiritual))
        _ = try await ContractExamples.client("getSubscription", status: 200).subscription()
        try await ContractExamples.client("deleteAccount", status: 204).deleteAccount()
        try await ContractExamples.client("logout", status: 204).logout(refreshToken: "r")
        try await ContractExamples.client("requestEmailLink", status: 202).requestEmailLink(email: "a@b.c")
        _ = try await ContractExamples.client("verifyEmailLink", status: 200).verifyEmailLink(token: "t")
        _ = try await ContractExamples.client("refreshTokens", status: 200).refreshTokens(refreshToken: "r")
        _ = try await ContractExamples.client("health", status: 200).health()
    }

    @Test func dreams() async throws {
        let dream = try await ContractExamples.client("getDream", status: 200).dream(id: id)
        #expect(!dream.title.isEmpty || dream.status != .ready)
        _ = try await ContractExamples.client("createDream", status: 201)
            .createDream(DreamSubmission(clientId: "client-1", text: "I was flying", details: nil, recordedAt: nil, recordingId: nil))
        let page = try await ContractExamples.client("listDreams", status: 200).listDreams()
        #expect(!page.items.isEmpty)
        _ = try await ContractExamples.client("updateDream", status: 200).updateDream(id: id, DreamPatch(notes: "n"))
        try await ContractExamples.client("deleteDream", status: 204).deleteDream(id: id)
        _ = try await ContractExamples.client("dreamStatus", status: 200).dreamProgress(id: id)
        _ = try await ContractExamples.client("retryDream", status: 202).retryDream(id: id)
        _ = try await ContractExamples.client("regenerateImage", status: 202).regenerateImage(id: id)
    }

    @Test func media() async throws {
        let card = try await ContractExamples.client("shareCard", status: 200).shareCard(id: id)
        guard case .ready = card else { Issue.record("Expected the card"); return }
        _ = try await ContractExamples.client("getDreamAudio", status: 200).dreamAudio(id: id, lens: .spiritual)
        _ = try await ContractExamples.client("requestDreamAudio", status: 202).requestDreamAudio(id: id, lens: .spiritual)
        _ = try await ContractExamples.client("recordingUploadUrl", status: 201).recordingUploadURL(contentType: "audio/m4a", sizeBytes: 100)
        _ = try await ContractExamples.client("transcribeRecording", status: 200).transcribeRecording(id: "rec_1")
    }

    @Test func insightsAndLibrary() async throws {
        let week = try await ContractExamples.client("weekInsight", status: 200).weekInsight()
        #expect(week.days.count == 7)
        _ = try await ContractExamples.client("monthInsight", status: 200).monthInsight()
        _ = try await ContractExamples.client("morningInsight", status: 200).morningInsight()
        let symbols = try await ContractExamples.client("listLibrarySymbols", status: 200).librarySymbols()
        #expect(!symbols.items.isEmpty)
        let symbol = try await ContractExamples.client("getLibrarySymbol", status: 200).librarySymbol(slug: "teeth")
        #expect(!symbol.lenses.isEmpty)
    }

    @Test func devicesAndAttestation() async throws {
        try await ContractExamples.client("registerDevice", status: 204).registerDevice(token: "abc", environment: .production)
        try await ContractExamples.client("unregisterDevice", status: 204).unregisterDevice(token: "abc")
        _ = try await ContractExamples.client("attestChallenge", status: 200).attestChallenge()
        try await ContractExamples.client("registerAttestKey", status: 204).registerAttestKey(keyId: "k", attestation: "a", challenge: "c")
    }
}

struct ContractErrorTests {
    /// Every error example of every operation carries a code the app knows (an unknown one would
    /// fall back to "internal error" and show the wrong screen).
    @Test func everyDocumentedErrorCodeIsKnown() throws {
        var checked = 0
        // /health answers 503 with its own status body (a degraded environment), not an error.
        for (operation, responses) in ContractExamples.all where operation != "health" {
            for (status, _) in responses {
                guard let code = Int(status), code >= 400, let body = ContractExamples.body(operation, code) else { continue }
                let raw = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any])["code"] as? String
                #expect(APIErrorCode(rawValue: raw ?? "") != nil, "\(operation) \(status): \(raw ?? "-")")
                if case .server(let server) = APIError.fromResponse(status: code, body: body, retryAfterHeader: nil) {
                    #expect(server.status == code)
                }
                checked += 1
            }
        }
        #expect(checked > 100)
    }

    @Test func premiumRequiredMeansThePaywall() throws {
        let body = try #require(ContractExamples.body("createDream", 402))
        let error = APIError.fromResponse(status: 402, body: body, retryAfterHeader: nil)
        #expect(error.code == .premiumRequired)
        #expect(ErrorState(error).action == .openPaywall)
    }

    @Test func rateLimitsCarryTheirDetails() throws {
        let body = try #require(ContractExamples.body("createDream", 429))
        let error = APIError.fromResponse(status: 429, body: body, retryAfterHeader: "60")
        guard case .server(let server) = error else { Issue.record("Expected a server error"); return }
        #expect(server.code == .rateLimited || server.code == .limitReached)
        #expect(server.retryAfter != nil || server.resetAt != nil)
    }
}
