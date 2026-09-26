import Foundation
import Testing
@testable import Dreamer

@MainActor
struct SettingsSyncTests {
    private func signedIn() -> AppState {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        return appState
    }

    @Test func reminderAndNightModeGoToTheProfile() {
        let appState = signedIn()
        appState.reminders.reminderMinutes = 6 * 60 + 45
        appState.reminders.morningReminder = false
        appState.reminders.nightModeAfter9 = false
        #expect(appState.unsyncedProfile == ProfileUpdate(reminderEnabled: false, reminderTime: "06:45", nightMode: false))
    }

    @Test func theFaceIDLockStaysOnTheDevice() {
        let appState = signedIn()
        appState.reminders.lockWithFaceID = true
        #expect(appState.unsyncedProfile == nil)
    }

    @Test func theServersProfileIsNotSentBack() {
        let appState = signedIn()
        appState.apply(UserProfile(id: "user-1", email: nil, name: nil, goal: nil, preferredLens: .spiritual,
                                   reminder: .init(enabled: false, time: "08:00"), timezone: "UTC", nightMode: false, createdAt: .now))
        #expect(appState.reminders.reminderMinutes == 8 * 60)
        #expect(appState.unsyncedProfile == nil)
    }

    @Test func travelUpdatesTheTimeZone() {
        let appState = signedIn()
        appState.timeZoneChanged(to: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(appState.unsyncedProfile?.timezone == "Asia/Tokyo")
        #expect(appState.profileWriteRequest != nil)
    }
}

@MainActor
struct AppLockTests {
    private func appState(lock: Bool) -> AppState {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.reminders.lockWithFaceID = lock
        return appState
    }

    @Test func aLockedAppOpensCoveredAndFaceIDOpensIt() async {
        let authenticator = MockAuthenticator()
        let lock = AppLock(appState: appState(lock: true), authenticator: authenticator)
        #expect(lock.isLocked)
        await lock.sceneChanged(active: true, background: false)
        #expect(!lock.isLocked)
        #expect(authenticator.attempts == 1)
    }

    @Test func leavingTheAppLocksItAgain() async {
        let lock = AppLock(appState: appState(lock: true), authenticator: MockAuthenticator())
        await lock.sceneChanged(active: true, background: false)
        await lock.sceneChanged(active: false, background: false)
        #expect(lock.isShielded)
        await lock.sceneChanged(active: false, background: true)
        #expect(lock.isLocked)
    }

    @Test func aFailedCheckKeepsItLocked() async {
        let authenticator = MockAuthenticator()
        authenticator.answer = false
        let lock = AppLock(appState: appState(lock: true), authenticator: authenticator)
        await lock.unlock()
        #expect(lock.isLocked)
    }

    @Test func withoutTheLockNothingIsCovered() async {
        let lock = AppLock(appState: appState(lock: false), authenticator: MockAuthenticator())
        #expect(!lock.isLocked)
        await lock.sceneChanged(active: false, background: true)
        #expect(!lock.isLocked && !lock.isShielded)
    }

    @Test func turningItOnNeedsACheckAndAPasscode() async {
        let state = appState(lock: false)
        let authenticator = MockAuthenticator()
        authenticator.isAvailable = false
        let lock = AppLock(appState: state, authenticator: authenticator)
        await lock.setEnabled(true)
        #expect(!state.reminders.lockWithFaceID)
        #expect(lock.alertMessage != nil)

        authenticator.isAvailable = true
        await lock.setEnabled(true)
        #expect(state.reminders.lockWithFaceID)
    }
}
