import Foundation
import Observation
import UIKit
@preconcurrency import UserNotifications

/// Where a tapped notification wants to go, handed from the app delegate to the SwiftUI root. A tap
/// on a cold start arrives before the root exists, so it waits here until the root reads it.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    private(set) var pending: NotificationLink?
    /// The backend push type of the tap (`push_opened`), nil for our local reminders.
    private(set) var pendingPushType: String?

    func receive(_ link: NotificationLink, pushType: String?) {
        pending = link
        pendingPushType = pushType
    }

    func consume() -> (link: NotificationLink, pushType: String?)? {
        guard let pending else { return nil }
        defer {
            self.pending = nil
            pendingPushType = nil
        }
        return (pending, pendingPushType)
    }
}

/// The UIKit side of notifications: taps (warm and cold start) and banners while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let link = NotificationLink(userInfo: userInfo) else { return }
        // Local reminders carry "link"; the backend's pushes carry "type".
        let pushType = userInfo["type"] as? String
        await MainActor.run { NotificationRouter.shared.receive(link, pushType: pushType) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
