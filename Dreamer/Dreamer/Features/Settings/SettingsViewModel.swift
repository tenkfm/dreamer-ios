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
    /// How the last restore ended, felt.
    private(set) var haptic: HapticEvent?
    private(set) var isRestoring = false
    private(set) var isDeleting = false
    private(set) var isSigningOut = false
    /// Why the last deletion failed (shown in the confirmation sheet).
    private(set) var deleteError: ErrorState?

    /// The system's subscription management (plan change, cancel), for subscribers.
    var isManagingSubscription = false

    private let appState: AppState
    private let purchases: any PurchaseService
    private let account: any AccountActions
    private let analytics: any Analytics
    private let dataExport: any DataExporting
    private let calendar: Calendar
    private let now: () -> Date

    init(appState: AppState, purchases: any PurchaseService, account: any AccountActions,
         analytics: any Analytics = NoopAnalytics(), dataExport: any DataExporting = MockDataExport(),
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.appState = appState
        self.purchases = purchases
        self.account = account
        self.analytics = analytics
        self.dataExport = dataExport
        self.calendar = calendar
        self.now = now
    }

    /// The voice dreams are read in; its id until the voice list has named it.
    var voiceName: String { appState.voiceName ?? appState.voiceID.capitalized }

    func openVoice() { appState.push(.voice, on: appState.selectedTab) }

    // MARK: Data export

    /// The export is being fetched: the row shows a spinner and further taps are ignored.
    private(set) var isExporting = false
    /// Set to present the share sheet with the export file.
    var exportFile: ExportFile?
    /// The file on disk until its sheet is gone (`exportFile` is cleared before the sheet closes).
    @ObservationIgnored private var writtenExport: URL?

    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// "Export my data": the server's JSON as is, to a temporary file for the share sheet. Nothing
    /// about it (its size included) is logged or reported.
    func exportData() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await dataExport.exportData()
            let url = try DataExportFile.write(data, on: now(), calendar: calendar)
            writtenExport = url
            exportFile = ExportFile(url: url)
        } catch let error as APIError {
            switch error {
            // The session ended and the refresh failed: the app is already back at sign-in.
            case .signedOut: return
            case .server(let server) where server.code == .authRequired || server.code == .authInvalidToken: return
            case .server(let server) where server.code == .rateLimited:
                alertMessage = String(localized: "You can export your data 3 times an hour. Try again later.")
            default:
                alertMessage = String(localized: "Couldn’t export your data. Check your connection and try again.")
            }
            haptic = HapticEvent(.error)
        } catch {
            haptic = HapticEvent(.error)
            alertMessage = String(localized: "Couldn’t export your data. Check your connection and try again.")
        }
    }

    /// The share sheet finished; `completed` is false when the user cancelled.
    func exportShared(completed: Bool) {
        if completed { haptic = HapticEvent(.success) }
        exportFile = nil
    }

    /// The sheet is gone (shared, cancelled or swiped away): the file with every dream goes too.
    func exportSheetDismissed() {
        if let writtenExport { DataExportFile.remove(writtenExport) }
        writtenExport = nil
        exportFile = nil
    }

    /// Settings -> Subscription: subscribers manage it in the App Store sheet, others see the plans.
    func openSubscription() {
        if appState.subscription != .none {
            isManagingSubscription = true
        } else {
            activeSheet = .subscription
        }
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
        set { appState.setPreferredLens(newValue) }
    }

    var subscriptionText: String {
        appState.subscription.plan?.title ?? String(localized: "Not active")
    }

    // MARK: Actions

    func makePaywallViewModel() -> PaywallViewModel {
        PaywallViewModel(purchases: purchases, appState: appState, placement: .settings, analytics: analytics) { [weak self] in
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
                haptic = HapticEvent(.success)
                alertMessage = String(localized: "Your \(plan.title.lowercased()) subscription is restored.")
            } else {
                haptic = HapticEvent(.warning)
                alertMessage = String(localized: "We couldn’t find a previous purchase.")
            }
        } catch {
            haptic = HapticEvent(.error)
            alertMessage = String(localized: "Restore failed. Please try again.")
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
