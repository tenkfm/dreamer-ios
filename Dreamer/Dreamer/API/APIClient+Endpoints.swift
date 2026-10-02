import Foundation
import OpenAPIRuntime

// Every phase 1 endpoint as a typed call returning domain models. Error responses never reach
// these switches: ErrorMiddleware turns them into APIError first, so `default` means a status the
// contract does not document.

extension APIClient {
    private func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    private func unexpected<T>(_ status: Int? = nil, operation: String = #function) throws(APIError) -> T {
        reportUnreadable(operation: operation)
        throw APIError.invalidResponse(status: status)
    }

    private func body<T>(operation: String = #function, _ read: () throws -> T) throws(APIError) -> T {
        do {
            return try read()
        } catch {
            reportUnreadable(operation: operation)
            throw APIError.invalidResponse(status: nil)
        }
    }


    // MARK: - System

    /// `GET /health`: true when the environment answers and its services are up.
    func health() async throws(APIError) -> Bool {
        let output = try await perform { try await client.health() }
        guard case .ok(let ok) = output else { return false }
        return try body { try ok.body.json.status == .ok }
    }

    // MARK: - Auth

    func signInWithApple(identityToken: String, authorizationCode: String?, nonce: String?,
                         givenName: String?, familyName: String?) async throws(APIError) -> AuthSession {
        let fullName: Components.Schemas.AppleSignIn.FullNamePayload? =
            givenName == nil && familyName == nil ? nil : .init(givenName: givenName, familyName: familyName)
        let output = try await perform {
            try await client.signInWithApple(body: .json(.init(identityToken: identityToken,
                                                               authorizationCode: authorizationCode,
                                                               nonce: nonce,
                                                               fullName: fullName)))
        }
        guard case .ok(let ok) = output else { return try unexpected() }
        return AuthSession(try body { try ok.body.json })
    }

    /// The id token from Google Sign-In; links an account with the same verified email or creates one.
    func signInWithGoogle(idToken: String, nonce: String?) async throws(APIError) -> AuthSession {
        let output = try await perform {
            try await client.signInWithGoogle(body: .json(.init(idToken: idToken, nonce: nonce)))
        }
        guard case .ok(let ok) = output else { return try unexpected() }
        return AuthSession(try body { try ok.body.json })
    }

    /// Always accepted (whether or not the address has an account).
    func requestEmailLink(email: String) async throws(APIError) {
        let output = try await perform { try await client.requestEmailLink(body: .json(.init(email: email))) }
        guard case .accepted = output else { return try unexpected() }
    }

    func verifyEmailLink(token: String) async throws(APIError) -> AuthSession {
        let output = try await perform { try await client.verifyEmailLink(body: .json(.init(token: token))) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return AuthSession(try body { try ok.body.json })
    }

    func refreshTokens(refreshToken: String) async throws(APIError) -> AuthSession {
        let output = try await perform { try await client.refreshTokens(body: .json(.init(refreshToken: refreshToken))) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return AuthSession(try body { try ok.body.json })
    }

    /// Ends this device's session; without a refresh token, every device's.
    func logout(refreshToken: String?) async throws(APIError) {
        let output = try await perform { try await client.logout(body: .json(.init(refreshToken: refreshToken))) }
        guard case .noContent = output else { return try unexpected() }
    }

    // MARK: - Profile

    func profile() async throws(APIError) -> UserProfile {
        let output = try await perform { try await client.getProfile() }
        guard case .ok(let ok) = output else { return try unexpected() }
        return UserProfile(try body { try ok.body.json })
    }

    func updateProfile(_ update: ProfileUpdate) async throws(APIError) -> UserProfile {
        let output = try await perform { try await client.updateProfile(body: .json(update.contract)) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return UserProfile(try body { try ok.body.json })
    }

    func deleteAccount() async throws(APIError) {
        let output = try await perform { try await client.deleteAccount() }
        guard case .noContent = output else { return try unexpected() }
    }

    /// Everything the backend holds about the user, as JSON (GDPR export).
    func exportData() async throws(APIError) -> Data {
        let output = try await perform { try await client.exportData() }
        guard case .ok(let ok) = output else { return try unexpected() }
        let export = try body { try ok.body.json }
        return try body { try JSONEncoder().encode(export) }
    }

    // MARK: - Dreams

    /// Idempotent by `clientId`: `created` is false when the server already had this dream.
    func createDream(_ submission: DreamSubmission) async throws(APIError) -> (dream: Dream, created: Bool) {
        let output = try await perform { try await client.createDream(body: .json(submission.contract)) }
        switch output {
        case .created(let created): return (try Dream(try body { try created.body.json }), true)
        case .ok(let ok): return (try Dream(try body { try ok.body.json }), false)
        default: return try unexpected()
        }
    }

    func listDreams(cursor: String? = nil, limit: Int = 20, emotion: Emotion? = nil, query: String? = nil)
    async throws(APIError) -> DreamPage {
        let emotionQuery = emotion.flatMap { Operations.ListDreams.Input.Query.EmotionPayload(rawValue: $0.rawValue) }
        let output = try await perform {
            try await client.listDreams(query: .init(cursor: cursor, emotion: emotionQuery, q: query, limit: limit))
        }
        guard case .ok(let ok) = output else { return try unexpected() }
        let list = try body { try ok.body.json }
        var items: [DreamSummary] = []
        for item in list.items { items.append(try DreamSummary(item)) }
        return DreamPage(items: items, nextCursor: list.nextCursor)
    }

    func dream(id dreamID: UUID) async throws(APIError) -> Dream {
        let output = try await perform { try await client.getDream(path: .init(id: id(dreamID))) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return try Dream(try body { try ok.body.json })
    }

    func updateDream(id dreamID: UUID, _ patch: DreamPatch) async throws(APIError) -> Dream {
        let output = try await perform {
            try await client.updateDream(path: .init(id: id(dreamID)), body: .json(.init(notes: patch.notes, title: patch.title)))
        }
        guard case .ok(let ok) = output else { return try unexpected() }
        return try Dream(try body { try ok.body.json })
    }

    func deleteDream(id dreamID: UUID) async throws(APIError) {
        let output = try await perform { try await client.deleteDream(path: .init(id: id(dreamID))) }
        guard case .noContent = output else { return try unexpected() }
    }

    func dreamProgress(id dreamID: UUID) async throws(APIError) -> DreamProgress {
        let output = try await perform { try await client.dreamStatus(path: .init(id: id(dreamID))) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return try DreamProgress(try body { try ok.body.json })
    }

    func retryDream(id dreamID: UUID) async throws(APIError) -> DreamProgress {
        let output = try await perform { try await client.retryDream(path: .init(id: id(dreamID))) }
        guard case .accepted(let accepted) = output else { return try unexpected() }
        return try DreamProgress(try body { try accepted.body.json })
    }

    /// The returned dream carries the new image version as `pending`.
    func regenerateImage(id dreamID: UUID) async throws(APIError) -> Dream {
        let output = try await perform { try await client.regenerateImage(path: .init(id: id(dreamID))) }
        guard case .accepted(let accepted) = output else { return try unexpected() }
        return try Dream(try body { try accepted.body.json })
    }

    func shareCard(id dreamID: UUID) async throws(APIError) -> ShareCardResult {
        let output = try await perform { try await client.shareCard(path: .init(id: id(dreamID))) }
        switch output {
        case .ok(let ok):
            let card = try body { try ok.body.json }
            guard let url = URL(string: card.url) else { return try unexpected() }
            return .ready(ShareCard(url: url, width: Int(card.width), height: Int(card.height)))
        case .accepted:
            return .rendering(retryAfter: 1)
        default:
            return try unexpected()
        }
    }

    func dreamAudio(id dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio {
        let lensQuery = Operations.GetDreamAudio.Input.Query.LensPayload(rawValue: lens.rawValue) ?? .psychology
        let output = try await perform {
            try await client.getDreamAudio(path: .init(id: id(dreamID)), query: .init(lens: lensQuery))
        }
        guard case .ok(let ok) = output else { return try unexpected() }
        return DreamAudio(try body { try ok.body.json })
    }

    /// Starts the voice-over of a lens (or joins the running job); poll `dreamAudio` while pending.
    func requestDreamAudio(id dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio {
        let lensQuery = Operations.RequestDreamAudio.Input.Query.LensPayload(rawValue: lens.rawValue) ?? .psychology
        let output = try await perform {
            try await client.requestDreamAudio(path: .init(id: id(dreamID)), query: .init(lens: lensQuery))
        }
        switch output {
        case .ok(let ok): return DreamAudio(try body { try ok.body.json })
        case .accepted(let accepted): return DreamAudio(try body { try accepted.body.json })
        default: return try unexpected()
        }
    }

    // MARK: - Recordings

    /// `contentType` must be one the backend accepts (`audio/m4a`, `audio/mp4`, `audio/aac`, ...);
    /// files are at most 20 MB.
    func recordingUploadURL(contentType: String, sizeBytes: Int) async throws(APIError) -> RecordingUpload {
        guard let type = Components.Schemas.RecordingUploadRequest.ContentTypePayload(rawValue: contentType) else {
            throw APIError.invalidResponse(status: nil)
        }
        let output = try await perform {
            try await client.recordingUploadUrl(body: .json(.init(contentType: type, sizeBytes: sizeBytes)))
        }
        guard case .created(let created) = output else { return try unexpected() }
        let upload = try body { try created.body.json }
        guard let url = URL(string: upload.uploadUrl) else { return try unexpected() }
        return RecordingUpload(recordingId: upload.recordingId, uploadURL: url, expiresAt: upload.expiresAt)
    }

    func transcribeRecording(id recordingID: String) async throws(APIError) -> String {
        let output = try await perform { try await client.transcribeRecording(path: .init(id: recordingID)) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return try body { try ok.body.json.text }
    }

    // MARK: - Insights

    func weekInsight() async throws(APIError) -> WeekInsight {
        let output = try await perform { try await client.weekInsight() }
        guard case .ok(let ok) = output else { return try unexpected() }
        return WeekInsight(try body { try ok.body.json })
    }

    /// `month` is "YYYY-MM"; nil means the current month in the user's time zone.
    func monthInsight(month: String? = nil) async throws(APIError) -> MonthInsight {
        let output = try await perform { try await client.monthInsight(query: .init(month: month)) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return MonthInsight(try body { try ok.body.json })
    }

    /// Home's one or two cards. Asked each time Home shows: they follow the hour and the journal.
    func homeCards() async throws(APIError) -> [HomeCard] {
        let output = try await perform { try await client.homeCards() }
        guard case .ok(let ok) = output else { return try unexpected() }
        return try body { try ok.body.json }.cards.map(HomeCard.init)
    }

    /// The voices to pick in Settings, in the order to show.
    func voices() async throws(APIError) -> VoiceList {
        let output = try await perform { try await client.listVoices() }
        guard case .ok(let ok) = output else { return try unexpected() }
        return VoiceList(try body { try ok.body.json })
    }

    // MARK: - Library

    func librarySymbols(query: String? = nil, category: SymbolCategory? = nil, cursor: String? = nil, limit: Int = 30)
    async throws(APIError) -> LibraryPage {
        let categoryQuery = category.flatMap { Operations.ListLibrarySymbols.Input.Query.CategoryPayload(rawValue: $0.rawValue) }
        let output = try await perform {
            try await client.listLibrarySymbols(query: .init(q: query, category: categoryQuery, cursor: cursor, limit: limit))
        }
        guard case .ok(let ok) = output else { return try unexpected() }
        let list = try body { try ok.body.json }
        return LibraryPage(items: list.items.map(LibrarySymbol.init), nextCursor: list.nextCursor)
    }

    func librarySymbol(slug: String) async throws(APIError) -> LibrarySymbol {
        let output = try await perform { try await client.getLibrarySymbol(path: .init(slug: slug)) }
        guard case .ok(let ok) = output else { return try unexpected() }
        return LibrarySymbol(try body { try ok.body.json })
    }

    // MARK: - Subscription

    func subscription() async throws(APIError) -> SubscriptionInfo {
        let output = try await perform { try await client.getSubscription() }
        guard case .ok(let ok) = output else { return try unexpected() }
        return SubscriptionInfo(try body { try ok.body.json })
    }

    // MARK: - Devices

    /// `token` is the APNs device token in hex.
    func registerDevice(token: String, environment: PushEnvironment) async throws(APIError) {
        let env: Components.Schemas.RegisterDevice.EnvironmentPayload = environment == .production ? .production : .sandbox
        let output = try await perform {
            try await client.registerDevice(body: .json(.init(token: token, environment: env, platform: .ios)))
        }
        guard case .noContent = output else { return try unexpected() }
    }

    func unregisterDevice(token: String) async throws(APIError) {
        let output = try await perform { try await client.unregisterDevice(body: .json(.init(token: token))) }
        guard case .noContent = output else { return try unexpected() }
    }

    // MARK: - App Attest

    func attestChallenge() async throws(APIError) -> AttestChallenge {
        let output = try await perform { try await client.attestChallenge() }
        guard case .ok(let ok) = output else { return try unexpected() }
        let challenge = try body { try ok.body.json }
        return AttestChallenge(challenge: challenge.challenge, expiresAt: challenge.expiresAt)
    }

    func registerAttestKey(keyId: String, attestation: String, challenge: String) async throws(APIError) {
        let output = try await perform {
            try await client.registerAttestKey(body: .json(.init(keyId: keyId, attestation: attestation, challenge: challenge)))
        }
        guard case .noContent = output else { return try unexpected() }
    }
}
