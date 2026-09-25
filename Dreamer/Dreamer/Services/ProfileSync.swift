import Foundation

/// The account profile on the backend (`/v1/me`).
protocol ProfileService: Sendable {
    func profile() async throws(APIError) -> UserProfile
    func update(_ update: ProfileUpdate) async throws(APIError) -> UserProfile
}

struct APIProfileService: ProfileService {
    let client: APIClient

    func profile() async throws(APIError) -> UserProfile { try await client.profile() }
    func update(_ update: ProfileUpdate) async throws(APIError) -> UserProfile { try await client.updateProfile(update) }
}

/// Keeps a local profile, for previews, tests and mock mode.
actor MockProfileService: ProfileService {
    private(set) var stored: UserProfile
    private(set) var updates: [ProfileUpdate] = []

    init(profile: UserProfile = UserProfile(id: "mock-user", email: nil, name: "Anna", goal: nil, preferredLens: .psychology,
                                            reminder: .init(enabled: true, time: "07:30"), timezone: "UTC",
                                            nightMode: true, createdAt: .now)) {
        stored = profile
    }

    func profile() async throws(APIError) -> UserProfile { stored }

    func update(_ update: ProfileUpdate) async throws(APIError) -> UserProfile {
        updates.append(update)
        if let goal = update.goal { stored.goal = goal }
        if let lens = update.preferredLens { stored.preferredLens = lens }
        if let enabled = update.reminderEnabled { stored.reminder.enabled = enabled }
        if let time = update.reminderTime { stored.reminder.time = time }
        if let timezone = update.timezone { stored.timezone = timezone }
        if let nightMode = update.nightMode { stored.nightMode = nightMode }
        return stored
    }
}

/// What to do with the profile after a sign-in or at launch.
enum ProfileSyncDirection: Equatable, Sendable {
    /// A new account: the quiz answers and settings made before signing up go to the server.
    case push
    /// An existing account: the server is the truth (another device may have changed it).
    case pull
}

/// Moves the anonymous onboarding answers into the account, and brings an existing account's
/// profile to this device. Failures are silent and retried at the next launch: the app works on
/// its local copy meanwhile.
@MainActor
struct ProfileSync {
    let appState: AppState
    let profiles: any ProfileService
    var timeZone: () -> TimeZone = { .current }

    func run(_ direction: ProfileSyncDirection) async {
        switch direction {
        case .push:
            if let profile = try? await profiles.update(localProfile()) {
                appState.apply(profile)
                appState.profileSynced()
            }
        case .pull:
            // A change made offline goes up first, or the pull would bring the old value back.
            await sendPending()
            guard appState.unsyncedProfile == nil, let profile = try? await profiles.profile() else { return }
            appState.apply(profile)
            // The server does insights in the user's time zone: keep it current after travel.
            let zone = timeZone().identifier
            if profile.timezone != zone {
                _ = try? await profiles.update(ProfileUpdate(timezone: zone))
            }
            appState.profileSynced()
        }
    }

    /// Sends the settings changed on this device. Offline and server failures keep them for the
    /// next try; a refused change (4xx) is dropped so it cannot block every later sync.
    func sendPending() async {
        guard let pending = appState.unsyncedProfile else { return }
        do {
            _ = try await profiles.update(pending)
            appState.profileUpdateSent(pending)
        } catch {
            switch error {
            case .server(let server) where (400..<500).contains(server.status) && server.status != 401 && server.status != 429:
                appState.profileUpdateSent(pending)
            default:
                break
            }
        }
    }

    /// Everything the user chose on this device before the account existed.
    func localProfile() -> ProfileUpdate {
        let minutes = appState.reminders.reminderMinutes
        return ProfileUpdate(
            goal: appState.goal,
            preferredLens: appState.preferredLens,
            reminderEnabled: appState.reminders.morningReminder,
            reminderTime: String(format: "%02d:%02d", minutes / 60, minutes % 60),
            timezone: timeZone().identifier,
            nightMode: appState.reminders.nightModeAfter9
        )
    }
}

/// The user's notes on a dream, on the backend (`PATCH /v1/dreams/{id}`).
protocol DreamNotesService: Sendable {
    func saveNotes(_ notes: String, dreamID: UUID) async throws(APIError)
}

extension APIClient: DreamNotesService {
    func saveNotes(_ notes: String, dreamID: UUID) async throws(APIError) {
        _ = try await updateDream(id: dreamID, DreamPatch(notes: notes))
    }
}
