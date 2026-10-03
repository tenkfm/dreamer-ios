import Foundation
import os

/// The voices dreams are read in (Settings -> Voice). The pick is the profile's `voice`: new
/// voice-overs and their videos use it, a dream already voiced keeps its voice.
protocol VoiceService: Sendable {
    func voices() async throws(APIError) -> VoiceList
    /// `PATCH /v1/me { voice }`; an id gone from the catalog is 400 `VALIDATION_FAILED`.
    func setVoice(_ id: String) async throws(APIError) -> UserProfile
}

extension APIClient: VoiceService {
    func setVoice(_ id: String) async throws(APIError) -> UserProfile {
        try await updateProfile(ProfileUpdate(voice: id))
    }
}

/// Mock mode and previews: the contract's two examples and the neutral voice, kept in memory.
/// River has no preview yet, like a voice right after a deploy.
final class MockVoiceService: VoiceService, @unchecked Sendable {
    static let list = VoiceList(items: [
        Voice(id: "eve", name: "Eve", gender: .female, accent: "american", description: "Warm audiobook narrator",
              previewURL: URL(string: "https://media.example.com/voices/previews/eve-8b1c0d2e4f6a.mp3"), isDefault: true),
        Voice(id: "george", name: "George", gender: .male, accent: "british", description: "Warm storyteller",
              previewURL: URL(string: "https://media.example.com/voices/previews/george-3f2a9c1b7d4e.mp3"), isDefault: false),
        Voice(id: "river", name: "River", gender: .neutral, accent: "american", description: "Calm, even narrator",
              previewURL: nil, isDefault: false)
    ], defaultVoiceID: "eve")

    private let state: OSAllocatedUnfairLock<(list: VoiceList, voice: String, failure: APIError?)>

    init(list: VoiceList = MockVoiceService.list, failure: APIError? = nil) {
        state = OSAllocatedUnfairLock(initialState: (list, list.defaultVoiceID, failure))
    }

    var voice: String { state.withLock { $0.voice } }

    func voices() async throws(APIError) -> VoiceList { state.withLock { $0.list } }

    func setVoice(_ id: String) async throws(APIError) -> UserProfile {
        try state.withLock { state -> Result<UserProfile, APIError> in
            if let failure = state.failure { return .failure(failure) }
            guard state.list.items.contains(where: { $0.id == id }) else {
                return .failure(.server(.init(code: .validationFailed, message: "voice", status: 400)))
            }
            state.voice = id
            return .success(UserProfile(id: "mock-user", email: nil, name: "Anna", goal: nil, preferredLens: .psychology,
                                        reminder: .init(enabled: true, time: "07:30"), timezone: "UTC", nightMode: true,
                                        voice: id, createdAt: .now))
        }.get()
    }
}
