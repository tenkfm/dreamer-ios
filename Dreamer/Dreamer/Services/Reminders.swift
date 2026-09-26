import Foundation
import Observation
@preconcurrency import UserNotifications

/// A local notification to schedule: a day and time in the user's calendar, and where a tap goes.
struct LocalNotification: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    /// Year, month, day, hour and minute in the current time zone.
    var fireDate: DateComponents
    var link: NotificationLink
}

/// Where tapping a notification opens the app.
enum NotificationLink: Equatable, Sendable {
    case record
    case dream(UUID)
    case subscription

    var userInfo: [String: String] {
        switch self {
        case .record: ["link": "record"]
        case .dream(let id): ["link": "dream", "dreamId": id.uuidString.lowercased()]
        case .subscription: ["link": "subscription"]
        }
    }

    /// Our local reminders and the backend's pushes (`type` + `dreamId`).
    init?(userInfo: [AnyHashable: Any]) {
        switch (userInfo["link"] ?? userInfo["type"]) as? String {
        case "record", "morning_reminder": self = .record
        case "subscription": self = .subscription
        case "dream", "interpretation_ready", "image_ready":
            guard let raw = userInfo["dreamId"] as? String, let id = UUID(uuidString: raw) else { return nil }
            self = .dream(id)
        default: return nil
        }
    }
}

enum NotificationPermission: Sendable {
    case notDetermined, authorized, denied
}

/// UNUserNotificationCenter behind a protocol, so scheduling is tested without the system.
@MainActor
protocol NotificationScheduling: AnyObject {
    func permission() async -> NotificationPermission
    func requestPermission() async -> Bool
    func pendingIDs() async -> [String]
    func add(_ notifications: [LocalNotification]) async
    func remove(ids: [String])
}

@MainActor
final class SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ notifications: [LocalNotification]) async {
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.userInfo = notification.link.userInfo
            let trigger = UNCalendarNotificationTrigger(dateMatching: notification.fireDate, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
        }
    }

    func remove(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// For previews, tests and mock mode.
@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    var currentPermission: NotificationPermission
    let grants: Bool
    private(set) var scheduled: [LocalNotification] = []
    private(set) var requests = 0

    init(permission: NotificationPermission = .authorized, grants: Bool = true) {
        currentPermission = permission
        self.grants = grants
    }

    func permission() async -> NotificationPermission { currentPermission }

    func requestPermission() async -> Bool {
        requests += 1
        currentPermission = grants ? .authorized : .denied
        return grants
    }

    func pendingIDs() async -> [String] { scheduled.map(\.id) }
    func add(_ notifications: [LocalNotification]) async { scheduled += notifications }
    func remove(ids: [String]) { scheduled.removeAll { ids.contains($0.id) } }
}

/// Which notifications should be waiting, as a pure function of the settings and the journal. The
/// morning reminder is scheduled one by one for the next week (so its words vary and a morning with
/// a dream already told is skipped) and planned again whenever the app opens, the settings or the
/// time zone change, or a dream is told.
struct ReminderPlanner {
    static let morningPrefix = "morning-"
    static let trialID = "trial-ends"
    static let daysAhead = 7

    var calendar: Calendar = .current

    /// Gentle, never guilt: a rotation keyed to the date, so the same morning reads the same.
    static let morningTexts: [(title: String, body: String)] = [
        (String(localized: "What did you dream last night?"), String(localized: "Tell it before it fades.")),
        (String(localized: "Good morning"), String(localized: "Your dream is still close. Tap to tell it.")),
        (String(localized: "A dream is waiting"), String(localized: "Catch it now, while you still remember.")),
        (String(localized: "Before the day begins"), String(localized: "Take a minute for last night’s dream.")),
        (String(localized: "Still half asleep?"), String(localized: "That’s the best time to tell your dream."))
    ]

    func morningReminders(settings: ReminderSettings, now: Date, streak: Int, toldToday: Bool) -> [LocalNotification] {
        guard settings.morningReminder else { return [] }
        let hour = settings.reminderMinutes / 60
        let minute = settings.reminderMinutes % 60
        var result: [LocalNotification] = []
        for offset in 0..<Self.daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > now else { continue }
            if offset == 0 && toldToday { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let text: (title: String, body: String)
            if result.isEmpty && streak >= 2 {
                // The next morning continues a streak: say so, softly.
                text = ("\(streak) mornings in a row", String(localized: "Keep it going - tell last night’s dream."))
            } else {
                let dayNumber = calendar.ordinality(of: .day, in: .era, for: fire) ?? offset
                text = Self.morningTexts[dayNumber % Self.morningTexts.count]
            }
            result.append(LocalNotification(id: Self.morningPrefix + Self.dayKey(components), title: text.title, body: text.body,
                                            fireDate: components, link: .record))
        }
        return result
    }

    /// Two days before a renewing trial turns paid, at the reminder time (the paywall promises it).
    func trialReminder(endsAt: Date?, settings: ReminderSettings, now: Date) -> LocalNotification? {
        guard let endsAt, let twoDaysBefore = calendar.date(byAdding: .day, value: -2, to: endsAt) else { return nil }
        let fire = calendar.date(bySettingHour: settings.reminderMinutes / 60, minute: settings.reminderMinutes % 60,
                                 second: 0, of: twoDaysBefore) ?? twoDaysBefore
        guard fire > now else { return nil }
        return LocalNotification(
            id: Self.trialID,
            title: String(localized: "Your free week ends in 2 days"),
            body: String(localized: "After that your yearly plan starts. You can cancel any time in your App Store settings."),
            fireDate: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            link: .subscription)
    }

    private static func dayKey(_ components: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// Keeps the pending notifications in line with the settings, and asks for the permission.
@MainActor
@Observable
final class ReminderController {
    /// Our explanation before the system alert (once, on the first Home after onboarding).
    var isPrePromptPresented = false
    private(set) var permission: NotificationPermission = .notDetermined

    @ObservationIgnored private let scheduler: any NotificationScheduling
    @ObservationIgnored private let appState: AppState
    @ObservationIgnored private let store: any DreamStore
    @ObservationIgnored private let planner: ReminderPlanner
    @ObservationIgnored private let now: () -> Date

    init(scheduler: any NotificationScheduling, appState: AppState, store: any DreamStore,
         planner: ReminderPlanner = ReminderPlanner(), now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.appState = appState
        self.store = store
        self.planner = planner
        self.now = now
    }

    static var preview: ReminderController {
        ReminderController(scheduler: MockNotificationScheduler(), appState: .preview(), store: InMemoryDreamStore())
    }

    /// Main opened: offer the reminder once, if it is on and never asked.
    func homeAppeared() async {
        permission = await scheduler.permission()
        guard !appState.reminderPromptShown, appState.reminders.morningReminder, permission == .notDetermined else { return }
        isPrePromptPresented = true
    }

    /// "Remind me" on the pre-prompt, or the Settings switch turned on.
    func enable() async {
        isPrePromptPresented = false
        appState.reminderPromptShown = true
        if await scheduler.permission() == .notDetermined {
            _ = await scheduler.requestPermission()
        }
        permission = await scheduler.permission()
        if !appState.reminders.morningReminder { appState.reminders.morningReminder = true }
        await reschedule()
    }

    /// "Not now": the reminder stays off until Settings turns it on.
    func decline() {
        isPrePromptPresented = false
        appState.reminderPromptShown = true
        appState.reminders.morningReminder = false
    }

    /// Replans every pending notification of ours.
    func reschedule() async {
        permission = await scheduler.permission()
        let ours = await scheduler.pendingIDs().filter {
            $0.hasPrefix(ReminderPlanner.morningPrefix) || $0 == ReminderPlanner.trialID
        }
        scheduler.remove(ids: ours)
        guard permission == .authorized, appState.isSignedIn else { return }
        let today = now()
        var planned = planner.morningReminders(settings: appState.reminders, now: today,
                                               streak: streak(until: today), toldToday: toldDream(on: today))
        if let trial = planner.trialReminder(endsAt: appState.trialEndsAt, settings: appState.reminders, now: today) {
            planned.append(trial)
        }
        await scheduler.add(planned)
    }

    private func toldDream(on day: Date) -> Bool {
        store.summaries.contains { planner.calendar.isDate($0.createdAt, inSameDayAs: day) }
    }

    /// Consecutive days with a dream, ending today or yesterday.
    private func streak(until day: Date) -> Int {
        let calendar = planner.calendar
        let days = Set(store.summaries.map { calendar.startOfDay(for: $0.createdAt) })
        var cursor = calendar.startOfDay(for: day)
        if !days.contains(cursor), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = yesterday }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
