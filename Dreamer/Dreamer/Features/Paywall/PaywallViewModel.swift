import Foundation
import Observation

@MainActor
@Observable
final class PaywallViewModel {
    var selectedPlan: Plan = .yearly
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var alertMessage: String?

    let perks = [
        "Personal interpretation in 3 lenses",
        "An image of every dream",
        "Private journal and recurring symbols",
        "Gentle morning reminders"
    ]

    private let purchases: any PurchaseService
    private let appState: AppState
    private let onFinish: (() -> Void)?

    /// - Parameter onFinish: called after a purchase, restore or close. When nil (onboarding / hard
    ///   paywall) the app state change itself moves the user to Main.
    init(purchases: any PurchaseService, appState: AppState, onFinish: (() -> Void)? = nil) {
        self.purchases = purchases
        self.appState = appState
        self.onFinish = onFinish
        selectedPlan = appState.subscription.plan ?? .yearly
    }

    var ctaTitle: String {
        switch selectedPlan {
        case .yearly: "Try 7 days free"
        case .weekly: "Subscribe for $6.99 a week"
        }
    }

    var termsText: String {
        switch selectedPlan {
        case .yearly: "Free for 7 days, then $39.99 a year. We remind you 2 days before it ends. Cancel anytime."
        case .weekly: "Renews every week until you cancel. Cancel anytime."
        }
    }

    var isBusy: Bool { isPurchasing || isRestoring }

    func purchase() async {
        guard !isBusy else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchases.purchase(selectedPlan)
            appState.activateSubscription(selectedPlan)
            onFinish?()
        } catch {
            alertMessage = "The purchase didn’t go through. Please try again."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            if let plan = try await purchases.restore() {
                appState.activateSubscription(plan)
                onFinish?()
            } else {
                alertMessage = "We couldn’t find a previous purchase."
            }
        } catch {
            alertMessage = "Restore failed. Please try again."
        }
    }

    /// The hard paywall has no way around it in App Store builds. Presented as a sheet (Settings ->
    /// Subscription) it can always be closed; Debug builds keep a close button for testing.
    var showsCloseButton: Bool {
        #if DEBUG
        true
        #else
        onFinish != nil
        #endif
    }

    func close() {
        if let onFinish {
            onFinish()
        } else {
            appState.enterMainForTesting()
        }
    }
}

extension Plan {
    var billingDescription: String {
        switch self {
        case .yearly: "$3.33 a month, billed yearly"
        case .weekly: "Billed every week"
        }
    }

    var displayPrice: String {
        switch self {
        case .yearly: "$39.99"
        case .weekly: "$6.99"
        }
    }

    var badge: String? {
        self == .yearly ? "7 days free" : nil
    }
}
