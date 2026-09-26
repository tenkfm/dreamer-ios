import CryptoKit
import Foundation
import os
import Testing
@testable import Dreamer

/// App Attest on a "device": keys are counters, an assertion is the client data hash itself, so a
/// test can check exactly what was signed.
final class FakeAttestService: AppAttestService, @unchecked Sendable {
    let supported: Bool
    private let state = OSAllocatedUnfairLock(initialState: (keys: 0, attested: [Data](), invalid: Set<String>()))

    init(supported: Bool = true) { self.supported = supported }

    var isSupported: Bool { supported }
    var generatedKeys: Int { state.withLock { $0.keys } }
    var attestHashes: [Data] { state.withLock { $0.attested } }
    func invalidate(_ keyID: String) { state.withLock { $0.invalid.insert(keyID) } }

    func generateKey() async throws -> String {
        state.withLock { $0.keys += 1; return "key-\($0.keys)" }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        state.withLock { $0.attested.append(clientDataHash) }
        return Data("attestation-\(keyID)".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        if state.withLock({ $0.invalid.contains(keyID) }) { throw CocoaError(.featureUnsupported) }
        return clientDataHash
    }
}

final class FakeAttestBackend: AttestBackend, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [String]())
    var registered: [String] { state.withLock { $0 } }

    func attestChallenge() async throws(APIError) -> AttestChallenge {
        AttestChallenge(challenge: "challenge-1", expiresAt: .now.addingTimeInterval(300))
    }

    func registerAttestKey(keyId: String, attestation: String, challenge: String) async throws(APIError) {
        state.withLock { $0.append("\(keyId)|\(challenge)") }
    }
}

struct AppAttestorTests {
    private func attestor(service: FakeAttestService = FakeAttestService(), backend: FakeAttestBackend = FakeAttestBackend(),
                          enforced: Bool = false) -> AppAttestor {
        AppAttestor(service: service, backend: backend, store: InMemorySecureStore(), enforced: enforced)
    }

    @Test func aKeyIsAttestedOnceWithTheChallengeHash() async throws {
        let service = FakeAttestService()
        let backend = FakeAttestBackend()
        let attestor = attestor(service: service, backend: backend)

        async let first = attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data("a".utf8), userID: "u1")
        async let second = attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data("b".utf8), userID: "u1")
        let (a, b) = try await (first, second)

        #expect(a?.keyID == "key-1" && b?.keyID == "key-1")
        #expect(service.generatedKeys == 1)
        #expect(backend.registered == ["key-1|challenge-1"])
        #expect(service.attestHashes == [Data(SHA256.hash(data: Data("challenge-1".utf8)))])
    }

    @Test func theAssertionSignsMethodPathAndBody() async throws {
        let attestor = attestor()
        let body = Data(#"{"clientId":"c1"}"#.utf8)
        let headers = try await attestor.headers(method: "post", pathWithQuery: "/v1/dreams/abc/audio?lens=spiritual", body: body, userID: "u1")
        let expected = Data(SHA256.hash(data: Data("POST /v1/dreams/abc/audio?lens=spiritual\n".utf8) + body))
        #expect(headers?.assertion == expected.base64EncodedString())
    }

    @Test func everyAccountHasItsOwnKey() async throws {
        let service = FakeAttestService()
        let attestor = attestor(service: service)
        _ = try await attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u1")
        let other = try await attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u2")
        #expect(other?.keyID == "key-2")
    }

    @Test func aLostKeyIsReplaced() async throws {
        let service = FakeAttestService()
        let attestor = attestor(service: service)
        _ = try await attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u1")
        service.invalidate("key-1")
        #expect(try await attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u1") == nil)
        let next = try await attestor.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u1")
        #expect(next?.keyID == "key-2")
    }

    @Test func theSimulatorSendsWithoutInSoftModeAndStopsWhenEnforced() async throws {
        let soft = attestor(service: FakeAttestService(supported: false))
        #expect(try await soft.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u1") == nil)

        let enforced = attestor(service: FakeAttestService(supported: false), enforced: true)
        await #expect(throws: APIError.self) {
            _ = try await enforced.headers(method: "POST", pathWithQuery: "/v1/dreams", body: Data(), userID: "u1")
        }
    }
}

struct AttestationMiddlewareTests {
    @Test func protectedRequestsCarryTheHeadersOthersDoNot() async throws {
        let attestor = AppAttestor(service: FakeAttestService(), backend: FakeAttestBackend(), store: InMemorySecureStore(), enforced: false)
        let middleware = AttestationMiddleware(attestor: attestor, userID: { "u1" })
        let (client, host) = StubURLProtocol.makeClient(tokens: StaticTokens(), innerMiddlewares: [middleware]) { request in
            request.url?.path() == "/v1/dreams" ? .json(201, APIClientTests.dreamJSON) : .json(200, #"{"days":[],"count":0}"#)
        }
        _ = try? await client.createDream(DreamSubmission(clientId: "client-abc", text: "I was flying", details: nil,
                                                          recordedAt: nil, recordingId: nil))
        _ = try? await client.weekInsight()

        let requests = StubURLProtocol.requests(for: host)
        let create = try #require(requests.first { $0.url?.path() == "/v1/dreams" })
        let assertion = try #require(create.value(forHTTPHeaderField: "X-App-Attest-Assertion"))
        #expect(create.value(forHTTPHeaderField: "X-App-Attest-Key-Id") == "key-1")
        // Signed over exactly the bytes that were sent.
        let signed = Data("POST /v1/dreams\n".utf8) + (create.httpBody ?? Data())
        #expect(assertion == Data(SHA256.hash(data: signed)).base64EncodedString())

        let week = try #require(requests.first { $0.url?.path() == "/v1/insights/week" })
        #expect(week.value(forHTTPHeaderField: "X-App-Attest-Key-Id") == nil)
    }
}
