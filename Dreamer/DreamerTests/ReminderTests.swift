import Foundation
import Testing
@testable import Dreamer

struct ReminderPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func aWeekOfMorningsAtTheChosenLocalTime() {
        let planner = ReminderPlanner(calendar: calendar)
        let plan = planner.morningReminders(settings: ReminderSettings(), now: date(1, 6), streak: 0, toldToday: false)

        #expect(plan.count == 7)
        #expect(plan.allSatisfy { $0.fireDate.hour == 7 && $0.fireDate.minute == 30 && $0.link == .record })
        #expect(plan.first?.fireDate.day == 1)
        #expect(Set(plan.map(\.id)).count == 7)
        // The words vary from morning to morning.
        #expect(Set(plan.map(\.title)).count > 1)
    }

    @Test func aMorningAlreadyPassedOrToldIsSkipped() {
        let planner = ReminderPlanner(calendar: calendar)
        let afterReminder = planner.morningReminders(settings: ReminderSettings(), now: date(1, 9), streak: 0, toldToday: false)
        #expect(afterReminder.first?.fireDate.day == 2)
        let told = planner.morningReminders(settings: ReminderSettings(), now: date(1, 6), streak: 0, toldToday: true)
        #expect(told.first?.fireDate.day == 2)
    }

    @Test func aStreakIsMentionedGently() {
        let plan = ReminderPlanner(calendar: calendar).morningReminders(settings: ReminderSettings(), now: date(1, 9), streak: 3, toldToday: true)
        #expect(plan.first?.title == "3 mornings in a row")
        #expect(plan.dropFirst().allSatisfy { !$0.title.contains("in a row") })
    }

    @Test func offMeansNothing() {
        var settings = ReminderSettings()
        settings.morningReminder = false
        #expect(ReminderPlanner(calendar: calendar).morningReminders(settings: settings, now: date(1, 6), streak: 0, toldToday: false).isEmpty)
    }

    @Test func theTrialReminderComesTwoDaysBeforeTheEnd() {
        let planner = ReminderPlanner(calendar: calendar)
        let reminder = planner.trialReminder(endsAt: date(8, 14), settings: ReminderSettings(), now: date(1, 14))
        #expect(reminder?.fireDate.day == 6)
        #expect(reminder?.fireDate.hour == 7)
        #expect(reminder?.link == .subscription)
        #expect(planner.trialReminder(endsAt: date(2, 14), settings: ReminderSettings(), now: date(1, 14)) == nil)
    }
}

@MainActor
struct ReminderControllerTests {
    private func signedIn(promptShown: Bool = false) -> AppState {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: false)
        appState.reminderPromptShown = promptShown
        return appState
    }

    @Test func theFirstHomeOffersTheReminderOnce() async {
        let scheduler = MockNotificationScheduler(permission: .notDetermined)
        let appState = signedIn()
        let controller = ReminderController(scheduler: scheduler, appState: appState, store: InMemoryDreamStore(seed: []))

        await controller.homeAppeared()
        #expect(controller.isPrePromptPresented)

        await controller.enable()
        #expect(scheduler.requests == 1)
        #expect(appState.reminderPromptShown)
        #expect(scheduler.scheduled.filter { $0.id.hasPrefix(ReminderPlanner.morningPrefix) }.count >= 6)

        await controller.homeAppeared()
        #expect(!controller.isPrePromptPresented)
    }

    @Test func notNowTurnsTheReminderOff() async {
        let appState = signedIn()
        let controller = ReminderController(scheduler: MockNotificationScheduler(permission: .notDetermined), appState: appState,
                                            store: InMemoryDreamStore(seed: []))
        await controller.homeAppeared()
        controller.decline()
        #expect(!appState.reminders.morningReminder)
        #expect(appState.reminderPromptShown)
    }

    @Test func reschedulingReplacesOnlyOurs() async {
        let scheduler = MockNotificationScheduler(permission: .authorized)
        let appState = signedIn(promptShown: true)
        let controller = ReminderController(scheduler: scheduler, appState: appState, store: InMemoryDreamStore(seed: []))
        await controller.reschedule()
        let first = scheduler.scheduled.count
        await controller.reschedule()
        #expect(scheduler.scheduled.count == first)

        appState.reminders.morningReminder = false
        await controller.reschedule()
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func deniedPermissionSchedulesNothing() async {
        let scheduler = MockNotificationScheduler(permission: .denied)
        let controller = ReminderController(scheduler: scheduler, appState: signedIn(promptShown: true), store: InMemoryDreamStore(seed: []))
        await controller.reschedule()
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func aTrialAddsItsReminder() async {
        let scheduler = MockNotificationScheduler(permission: .authorized)
        let appState = signedIn(promptShown: true)
        appState.applyEntitlement(EntitlementState(isPremium: true, plan: .yearly, expiresAt: .now.addingTimeInterval(7 * 86_400),
                                                   willRenew: true, isTrial: true))
        let controller = ReminderController(scheduler: scheduler, appState: appState, store: InMemoryDreamStore(seed: []))
        await controller.reschedule()
        #expect(scheduler.scheduled.contains { $0.id == ReminderPlanner.trialID })
    }
}

@MainActor
struct NotificationLinkTests {
    @Test func linksComeFromRemindersAndPushes() {
        let id = UUID()
        #expect(NotificationLink(userInfo: ["link": "record"]) == .record)
        #expect(NotificationLink(userInfo: ["type": "interpretation_ready", "dreamId": id.uuidString]) == .dream(id))
        #expect(NotificationLink(userInfo: ["type": "something_else"]) == nil)
    }

    @Test func tappingTheReminderOpensRecord() {
        let appState = AppState.preview()
        appState.handle(.record)
        #expect(appState.isRecordFlowPresented)
    }

    @Test func aPushAboutADreamOpensIt() {
        let appState = AppState.preview()
        let id = UUID()
        appState.handle(.dream(id))
        #expect(appState.selectedTab == .journal)
        #expect(appState.path(for: .journal) == [.interpretation(id)])
    }

    @Test func nothingHappensBeforeMain() {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.handle(.record)
        #expect(!appState.isRecordFlowPresented)
    }
}
