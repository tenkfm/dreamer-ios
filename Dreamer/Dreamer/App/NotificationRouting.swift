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

    // The completion-handler forms, with the handler called on the main thread. The async forms
    // hand their result back to UIKit from a thread of the concurrency pool, and UIKit asserts on
    // the main thread there: tapping any notification crashed the app.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let link = NotificationLink(userInfo: userInfo)
        // Local reminders carry "link"; the backend's pushes carry "type".
        let pushType = userInfo["type"] as? String
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let link { NotificationRouter.shared.receive(link, pushType: pushType) }
                done()
            }
        }
    }

    /// The backend's pushes say a dream is ready, which the open app already shows; our reminders
    /// still appear as banners.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let options: UNNotificationPresentationOptions = notification.request.content.userInfo["type"] == nil ? [.banner, .sound] : []
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async { done(options) }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushRegistration.shared.received(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // No push on the simulator or without the capability; reminders still work.
    }
}

/// The APNs token of this install, as the backend stores it (hex).
@MainActor
@Observable
final class PushRegistration {
    static let shared = PushRegistration()

    private(set) var token: String?

    func received(_ deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}
