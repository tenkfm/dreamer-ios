import Foundation

final class UserDefaultsPreferencesStore: PreferencesStore {
    private let defaults: UserDefaults
    private let key = "dreamer.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(UserPreferences.self, from: data)
        else { return UserPreferences() }
        return preferences
    }

    func save(_ preferences: UserPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Non-persistent store for previews and tests.
final class InMemoryPreferencesStore: PreferencesStore {
    private(set) var stored: UserPreferences

    init(_ preferences: UserPreferences = UserPreferences()) {
        stored = preferences
    }

    func load() -> UserPreferences { stored }
    func save(_ preferences: UserPreferences) { stored = preferences }
}
