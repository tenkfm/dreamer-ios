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
    var isSignOutConfirmationPresented = false
    var alertMessage: String?
    private(set) var isRestoring = false
    private(set) var isDeleting = false
    private(set) var isSigningOut = false
    /// Why the last deletion failed (shown in the confirmation sheet).
    private(set) var deleteError: ErrorState?

    private let appState: AppState
    private let purchases: any PurchaseService
    private let account: any AccountActions
    private let calendar: Calendar

    init(appState: AppState, purchases: any PurchaseService, account: any AccountActions, calendar: Calendar = .current) {
        self.appState = appState
        self.purchases = purchases
        self.account = account
        self.calendar = calendar
    }

    // MARK: Preferences

    var morningReminder: Bool {
        get { appState.reminders.morningReminder }
        set { appState.reminders.morningReminder = newValue }
    }

    var nightModeAfter9: Bool {
        get { appState.reminders.nightModeAfter9 }
        set {
            appState.reminders.nightModeAfter9 = newValue
            appState.resetNightModeOverride()
        }
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
            let entitlement = try await purchases.restore()
            if entitlement.isPremium {
                let plan = entitlement.plan ?? .yearly
                appState.activateSubscription(plan)
                alertMessage = "Your \(plan.title.lowercased()) subscription is restored."
            } else {
                alertMessage = "We couldn’t find a previous purchase."
            }
        } catch {
            alertMessage = "Restore failed. Please try again."
        }
    }

    var hasSubscription: Bool { appState.subscription != .none }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await account.signOut()
    }

    /// "Delete account and all dreams": the backend deletes everything, then the device is reset to
    /// a fresh install (Welcome). On failure nothing is removed and the sheet says why.
    func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }
        do {
            try await account.deleteAccount()
            isDeleteConfirmationPresented = false
        } catch {
            deleteError = ErrorState(error)
        }
    }

    func cancelDelete() {
        isDeleteConfirmationPresented = false
        deleteError = nil
    }
}
