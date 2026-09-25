import Foundation
import Testing
@testable import Dreamer

@MainActor
struct ProfileSyncTests {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    @Test func newAccountSendsTheQuizAnswersAndSettings() async throws {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.saveQuizAnswers(goal: .someone, lens: .dreamBook)
        appState.reminders.reminderMinutes = 6 * 60 + 45
        appState.reminders.nightModeAfter9 = false
        appState.signedIn(userID: "user-1", isNewUser: true)
        #expect(appState.pendingProfileSync == .push)

        let profiles = MockProfileService()
        await ProfileSync(appState: appState, profiles: profiles, timeZone: { warsaw }).run(.push)

        let sent = try #require(await profiles.updates.first)
        #expect(sent.goal == .someone)
        #expect(sent.preferredLens == .dreamBook)
        #expect(sent.reminderTime == "06:45")
        #expect(sent.reminderEnabled == true)
        #expect(sent.timezone == "Europe/Warsaw")
        #expect(sent.nightMode == false)
        #expect(appState.pendingProfileSync == nil)
    }

    @Test func existingAccountTakesTheServerProfile() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        #expect(appState.pendingProfileSync == .pull)

        let profiles = MockProfileService(profile: UserProfile(
            id: "user-1", email: "anna@example.com", name: "Maria Lopez", goal: .remember, preferredLens: .spiritual,
            reminder: .init(enabled: false, time: "08:15"), timezone: "Europe/Warsaw", nightMode: false, createdAt: .now))
        await ProfileSync(appState: appState, profiles: profiles, timeZone: { warsaw }).run(.pull)

        #expect(appState.userName == "Maria")
        #expect(appState.goal == .remember)
        #expect(appState.preferredLens == .spiritual)
        #expect(appState.reminders.morningReminder == false)
        #expect(appState.reminders.reminderMinutes == 8 * 60 + 15)
        #expect(appState.reminders.nightModeAfter9 == false)
        #expect(await profiles.updates.isEmpty)
    }

    @Test func travelUpdatesTheTimeZone() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        let profiles = MockProfileService()
        await ProfileSync(appState: appState, profiles: profiles, timeZone: { warsaw }).run(.pull)

        #expect(await profiles.updates.map(\.timezone) == ["Europe/Warsaw"])
    }

    @Test func offlineSyncTriesAgainLater() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: true)
        let (client, _) = StubURLProtocol.makeClient(tokens: StaticTokens()) { _ in
            .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet))
        }
        await ProfileSync(appState: appState, profiles: APIProfileService(client: client)).run(.push)

        #expect(appState.pendingProfileSync == .push)
    }

    @Test func greetingWithoutANameHasNoComma() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 8))!
        let viewModel = HomeViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: InMemoryDreamStore(seed: []),
                                      catalog: MockSymbolCatalog(), now: { morning }, calendar: calendar)
        #expect(viewModel.greeting == "Good morning")
    }
}
