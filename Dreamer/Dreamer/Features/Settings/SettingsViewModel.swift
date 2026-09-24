import Foundation
import Observation

/// 14 Settings. Toggles and pickers write straight to AppState.
@MainActor
@Observable
final class SettingsViewModel {
    enum Sheet: String, Identifiable {
        case reminderTime, lens, subscription
        var id: String { rawValue }
    }

    var activeSheet: Sheet?
    var isDeleteConfirmationPresented = false
    var alertMessage: String?
    private(set) var isRestoring = false

    private let appState: AppState
    private let purchases: any PurchaseService
    private let store: any DreamStore
    private let calendar: Calendar

    init(appState: AppState, purchases: any PurchaseService, store: any DreamStore, calendar: Calendar = .current) {
        self.appState = appState
        self.purchases = purchases
        self.store = store
        self.calendar = calendar
    }

    // MARK: Preferences

    var morningReminder: Bool {
        get { appState.reminders.morningReminder }
        set { appState.reminders.morningReminder = newValue }
    }

    var nightModeAfter9: Bool {
        get { appState.reminders.nightModeAfter9 }
        set { appState.reminders.nightModeAfter9 = newValue }
    }

    var lockWithFaceID: Bool {
        get { appState.reminders.lockWithFaceID }
        set { appState.reminders.lockWithFaceID = newValue }
    }

    var reminderTime: Date {
        get {
            let minutes = appState.reminders.reminderMinutes
            return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
        set {
            let parts = calendar.dateComponents([.hour, .minute], from: newValue)
            appState.reminders.reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    var reminderTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: reminderTime)
    }

    var preferredLens: Lens {
        get { appState.preferredLens }
        set { appState.preferredLens = newValue }
    }

    var subscriptionText: String {
        appState.subscription.plan?.title ?? "Not active"
    }

    // MARK: Actions

    func makePaywallViewModel() -> PaywallViewModel {
        PaywallViewModel(purchases: purchases, appState: appState) { [weak self] in
            self?.activeSheet = nil
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            if let plan = try await purchases.restore() {
                appState.activateSubscription(plan)
                alertMessage = "Your \(plan.title.lowercased()) subscription is restored."
            } else {
                alertMessage = "We couldn’t find a previous purchase."
            }
        } catch {
            alertMessage = "Restore failed. Please try again."
        }
    }

    /// "Delete account and all dreams": wipes dreams and preferences, back to Welcome.
    func deleteEverything() {
        store.deleteAll()
        appState.reset()
    }
}
