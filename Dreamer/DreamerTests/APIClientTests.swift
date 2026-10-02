import Foundation
import Testing
@testable import Dreamer

/// Fixed access token for tests of private routes.
struct StaticTokens: AccessTokenProvider {
    var token = "access-1"
    func accessToken() async throws -> String? { token }
    func refreshAfterRejection(of token: String) async throws -> String { throw APIError.signedOut }
}

struct APIClientTests {
    static let dreamJSON = """
    {
      "id": "0b6f3c55-1d3c-4b8e-9f1e-2c7a8e5d4f10",
      "clientId": "d7e1c6f2-local",
      "createdAt": "2026-09-24T06:12:00.000Z",
      "recordedAt": null,
      "title": "The house with endless stairs",
      "text": "I was back in my grandmother's house.",
      "emotions": ["anxiety", "confusion"],
      "recurrence": null,
      "someoneSpecific": true,
      "status": "ready",
      "analysisStep": 4,
      "errorCode": null,
      "mainLens": "spiritual",
      "interpretation": {
        "lenses": { "psychology": "P text", "spiritual": "S text", "dreamBook": "D text" },
        "forYou": "For you",
        "symbols": [{ "name": "Staircase down", "meaning": "Progress", "icon": "stairs", "keyword": "stairs" }],
        "safetyFlag": false
      },
      "image": { "status": "pending", "url": null, "previewUrl": null, "thumbnailUrl": null, "width": null, "height": null, "version": 1 },
      "audio": { "psychology": null, "spiritual": { "status": "ready", "url": "https://media.test/a.mp3", "durationSec": 64.5 }, "dreamBook": null },
      "notes": "",
      "updatedAt": "2026-09-24T06:12:09Z"
    }
    """

    @Test func healthIsPublicAndParsed() async throws {
        let (client, host) = StubURLProtocol.makeClient { _ in
            .json(200, #"{"status":"ok","version":"0.1.0","uptimeSec":10,"services":{"database":"up","redis":"up"}}"#)
        }
        #expect(try await client.health())
        #expect(StubURLProtocol.requests(for: host).first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func dreamDetailWithNullsMapsToDomain() async throws {
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in .json(200, Self.dreamJSON) }
        let dream = try await client.dream(id: UUID(uuidString: "0B6F3C55-1D3C-4B8E-9F1E-2C7A8E5D4F10")!)

        #expect(dream.title == "The house with endless stairs")
        #expect(dream.status == .ready)
        #expect(dream.errorCode == nil)
        #expect(dream.recurrence == .never)
        #expect(dream.mainLens == .spiritual)
        #expect(dream.interpretation?.text(for: .dreamBook) == "D text")
        #expect(dream.interpretation?.readDurations[.spiritual] == 64.5)
        #expect(dream.symbols.first?.glyph == .stairs)
        #expect(dream.image?.status == .pending)
        #expect(dream.image?.url == nil)
        #expect(dream.audio[.spiritual]?.url?.host() == "media.test")
        #expect(dream.audio[.psychology] == nil)

        let request = try #require(StubURLProtocol.requests(for: host).first)
        #expect(request.url?.path() == "/v1/dreams/0b6f3c55-1d3c-4b8e-9f1e-2c7a8e5d4f10")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    @Test func dreamListLastPageHasNoCursor() async throws {
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(200, """
            {"items":[{"id":"0b6f3c55-1d3c-4b8e-9f1e-2c7a8e5d4f10","createdAt":"2026-09-24T06:12:00.000Z",
            "weekOf":"2026-09-21","title":null,"status":"analyzing","emotions":["joy"],"thumbnailUrl":null,
            "symbols":["stairs"],"snippet":null}],"nextCursor":null}
            """)
        }
        let page = try await client.listDreams(limit: 20, emotion: .joy, query: "stairs")

        #expect(page.nextCursor == nil)
        #expect(page.items.first?.status == .analyzing)
        #expect(page.items.first?.thumbnailURL == nil)
        let query = StubURLProtocol.requests(for: host).first?.url?.query() ?? ""
        #expect(query.contains("emotion=joy"))
        #expect(query.contains("q=stairs"))
        #expect(query.contains("limit=20"))
    }

    @Test func createDreamIsIdempotentAndSendsDetails() async throws {
        let recorder = BodyRecorder()
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens(), middlewares: [recorder]) { _ in
            .json(200, Self.dreamJSON)
        }
        let submission = DreamSubmission(clientId: "d7e1c6f2-local", text: "I was back in my grandmother's house.",
                                         details: .init(emotions: [.anxiety], recurrence: .sometimes, someoneSpecific: true),
                                         recordedAt: nil, recordingId: nil)
        let result = try await client.createDream(submission)

        #expect(result.created == false)
        let body = try #require(recorder.last)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["clientId"] as? String == "d7e1c6f2-local")
        #expect((json["details"] as? [String: Any])?["recurrence"] as? String == "sometimes")
    }

    @Test func premiumRequiredBecomesATypedError() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(402, #"{"error":{"code":"PREMIUM_REQUIRED","message":"Subscribe"}}"#)
        }
        await #expect(throws: APIError.self) { _ = try await client.subscription() }
        do {
            _ = try await client.subscription()
        } catch {
            #expect(error.code == .premiumRequired)
        }
    }

    @Test func rateLimitCarriesRetryAfterAndReset() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .json(429, #"{"error":{"code":"RATE_LIMITED","message":"Daily limit","details":{"retryAfterSec":3600,"limit":"interpretations_per_day","max":10,"resetAt":"2026-09-26T00:00:00.000Z"}}}"#,
                  headers: ["Retry-After": "120"])
        }
        do {
            _ = try await client.weekInsight()
            Issue.record("Expected a rate limit error")
        } catch {
            guard case .server(let server) = error else { Issue.record("Unexpected \(error)"); return }
            #expect(server.code == .rateLimited)
            #expect(server.retryAfter == 120)
            #expect(server.limit == "interpretations_per_day")
            #expect(server.resetAt == APIDates.parse("2026-09-26T00:00:00Z"))
        }
    }

    @Test func unknownCodeIsHandledAsInternalError() {
        let error = APIError.fromResponse(status: 500, body: Data(#"{"error":{"code":"SOMETHING_NEW","message":"x"}}"#.utf8),
                                          retryAfterHeader: nil)
        #expect(error.code == .internalError)
    }

    @Test func noConnectionIsOffline() async {
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet))
        }
        do {
            _ = try await client.profile()
            Issue.record("Expected offline")
        } catch {
            #expect(error == .offline)
        }
    }

    @Test func privateRouteWithoutSessionFailsFast() async {
        let (client, host) = StubURLProtocol.makeClient(tokens: SignedOutTokens()) { _ in .json(200, "{}") }
        do {
            _ = try await client.profile()
            Issue.record("Expected signedOut")
        } catch {
            #expect(error == .signedOut)
        }
        #expect(StubURLProtocol.requests(for: host).isEmpty)
    }
}

private struct SignedOutTokens: AccessTokenProvider {
    func accessToken() async throws -> String? { nil }
    func refreshAfterRejection(of token: String) async throws -> String { throw APIError.signedOut }
}

struct APIClientRefreshTests {
    /// Hands out "old" first; after a rejection, "new".
    actor RotatingTokens: AccessTokenProvider {
        private(set) var current = "old"
        private(set) var refreshes = 0
        func accessToken() async throws -> String? { current }
        func refreshAfterRejection(of token: String) async throws -> String {
            refreshes += 1
            current = "new"
            return current
        }
    }

    @Test func expiredTokenIsRefreshedAndTheRequestRetried() async throws {
        let tokens = RotatingTokens()
        let (client, host) = StubURLProtocol.makeClient(tokens: tokens) { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
                ? .json(200, #"{"days":[],"count":0}"#)
                : .json(401, #"{"error":{"code":"AUTH_INVALID_TOKEN","message":"Session expired"}}"#)
        }
        let week = try await client.weekInsight()

        #expect(week.count == 0)
        #expect(await tokens.refreshes == 1)
        #expect(StubURLProtocol.requests(for: host).map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer new"])
    }
}
