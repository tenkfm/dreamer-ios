import CryptoKit
import DeviceCheck
import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Apple's App Attest service behind a protocol (the simulator does not support it).
protocol AppAttestService: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct SystemAppAttestService: AppAttestService {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

/// The backend's attestation endpoints.
protocol AttestBackend: Sendable {
    func attestChallenge() async throws(APIError) -> AttestChallenge
    func registerAttestKey(keyId: String, attestation: String, challenge: String) async throws(APIError)
}

extension APIClient: AttestBackend {}

/// Proves to the backend that requests which cost money (a dream, a retry, an image, a voice-over,
/// a transcription) come from the real app on a real iPhone. One App Attest key per account: it is
/// generated, attested against a fresh challenge and registered once, its id kept in the Keychain;
/// each protected request then carries an assertion over its method, path and body.
actor AppAttestor {
    struct Headers: Equatable, Sendable {
        var keyID: String
        var assertion: String
    }

    private let service: any AppAttestService
    private let backend: any AttestBackend
    private let store: any SecureStore
    /// Soft mode (the backend logs missing assertions): an iPhone or simulator that cannot attest
    /// still sends. Enforced: it stops before sending (the backend would refuse anyway).
    private let enforced: Bool
    private var registration: Task<String?, Never>?
    private var registrationFailed = false

    static let storeKey = "appAttest.keys"

    init(service: any AppAttestService, backend: any AttestBackend, store: any SecureStore, enforced: Bool) {
        self.service = service
        self.backend = backend
        self.store = store
        self.enforced = enforced
    }

    /// The headers for a protected request; nil when this device cannot attest in soft mode.
    func headers(method: String, pathWithQuery: String, body: Data, userID: String) async throws(APIError) -> Headers? {
        guard service.isSupported, let keyID = await key(for: userID) else {
            if enforced { throw APIError.server(.init(code: .attestationRequired, message: "", status: 403)) }
            return nil
        }
        let clientData = Data("\(method.uppercased()) \(pathWithQuery)\n".utf8) + body
        do {
            let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
            return Headers(keyID: keyID, assertion: assertion.base64EncodedString())
        } catch {
            // The key is gone (restored backup, reinstall): forget it, a new one is made next time.
            forget(userID: userID)
            if enforced { throw APIError.server(.init(code: .attestationRequired, message: "", status: 403)) }
            return nil
        }
    }

    /// Sign-out and account deletion.
    func reset() {
        try? store.set(nil, for: Self.storeKey)
        registrationFailed = false
    }

    // MARK: Key

    private func key(for userID: String) async -> String? {
        if let keyID = keys()[userID] { return keyID }
        guard !registrationFailed else { return nil }
        if let registration { return await registration.value }
        let task = Task { await self.register(userID: userID) }
        registration = task
        let keyID = await task.value
        registration = nil
        return keyID
    }

    private func register(userID: String) async -> String? {
        do {
            let keyID = try await service.generateKey()
            let challenge = try await backend.attestChallenge().challenge
            let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
            try await backend.registerAttestKey(keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge)
            var all = keys()
            all[userID] = keyID
            try? store.set(try? JSONEncoder().encode(all), for: Self.storeKey)
            return keyID
        } catch {
            // Not again this session (Apple's service down, the server not configured yet).
            registrationFailed = true
            return nil
        }
    }

    private func keys() -> [String: String] {
        guard let data = try? store.data(for: Self.storeKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func forget(userID: String) {
        var all = keys()
        all[userID] = nil
        try? store.set(try? JSONEncoder().encode(all), for: Self.storeKey)
    }
}

/// Adds the App Attest headers to the requests the backend protects. Sits inside the retry, so a
/// retried request gets a fresh assertion (their counter only goes up).
struct AttestationMiddleware: ClientMiddleware {
    let attestor: AppAttestor
    /// The signed-in user (the key belongs to the account).
    let userID: @Sendable () async -> String?

    static let protectedOperations: Set<String> = [
        "createDream", "retryDream", "regenerateImage", "requestDreamAudio", "recordingUploadUrl", "transcribeRecording"
    ]

    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
    async throws -> (HTTPResponse, HTTPBody?) {
        guard Self.protectedOperations.contains(operationID), let userID = await userID() else {
            return try await next(request, body, baseURL)
        }
        // The exact bytes are signed, so the body is read once and sent as read.
        let bytes: Data = if let body { try await Data(collecting: body, upTo: 1024 * 1024) } else { Data() }
        let path = baseURL.path(percentEncoded: true).trimmingSuffix("/") + (request.path ?? "")
        var request = request
        if let headers = try await attestor.headers(method: request.method.rawValue, pathWithQuery: path, body: bytes, userID: userID) {
            request.headerFields[HTTPField.Name("X-App-Attest-Key-Id")!] = headers.keyID
            request.headerFields[HTTPField.Name("X-App-Attest-Assertion")!] = headers.assertion
        }
        return try await next(request, body == nil ? nil : HTTPBody(bytes), baseURL)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
