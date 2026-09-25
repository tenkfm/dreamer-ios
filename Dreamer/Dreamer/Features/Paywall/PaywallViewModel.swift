import Foundation
import Observation

@MainActor
@Observable
final class PaywallViewModel {
    enum ProductsState: Equatable {
        case loading
        case loaded([PaywallProduct])
        /// The store did not answer: no prices can be shown, so nothing can be bought.
        case failed
    }

    /// Where the paywall was shown, for `paywall_viewed`.
    enum Placement: String, Sendable {
        case onboarding, gate, settings, analysis, record
    }

    var selectedPlan: Plan = .yearly
    private(set) var productsState: ProductsState = .loading
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
    private let analytics: any Analytics
    private let placement: Placement
    private let onFinish: (() -> Void)?
    private var hasReportedView = false

    /// - Parameter onFinish: called after a purchase, restore or close. When nil (onboarding / hard
    ///   paywall) the app state change itself moves the user to Main.
    init(purchases: any PurchaseService, appState: AppState, placement: Placement = .gate,
         analytics: any Analytics = NoopAnalytics(), onFinish: (() -> Void)? = nil) {
        self.purchases = purchases
        self.appState = appState
        self.placement = placement
        self.analytics = analytics
        self.onFinish = onFinish
        selectedPlan = appState.subscription.plan ?? .yearly
    }

    /// Once per presentation.
    func viewed() {
        guard !hasReportedView else { return }
        hasReportedView = true
        analytics.track(.paywallViewed(placement: placement.rawValue, variant: appState.paywallVariant.rawValue))
    }

    /// A plan card was tapped.
    func select(_ plan: Plan) {
        guard plan != selectedPlan else { return }
        selectedPlan = plan
        analytics.track(.planSelected(plan: plan.rawValue))
    }

    // MARK: Products

    func loadProducts() async {
        if case .loaded = productsState { return }
        do {
            let products = try await purchases.products()
            productsState = products.isEmpty ? .failed : .loaded(products)
            if !products.contains(where: { $0.plan == selectedPlan }), let first = products.first {
                selectedPlan = first.plan
            }
        } catch {
            productsState = .failed
        }
    }

    func reloadProducts() async {
        productsState = .loading
        await loadProducts()
    }

    var products: [PaywallProduct] {
        if case .loaded(let products) = productsState { return products }
        return []
    }

    var selectedProduct: PaywallProduct? { products.first { $0.plan == selectedPlan } }

    // MARK: Copy (App Review 3.1.2: price, period, trial and auto-renewal next to the button)

    var ctaTitle: String {
        guard let product = selectedProduct else { return "Continue" }
        if let trial = product.trial { return "Try \(trial.period.trialPhrase) free" }
        return "Subscribe for \(product.displayPrice) a \(product.period.phrase)"
    }

    var termsText: String {
        guard let product = selectedProduct else { return "" }
        let renewal = "Renews automatically until you cancel, at least 24 hours before the period ends. Cancel anytime in Settings."
        if let trial = product.trial {
            return "Free for \(trial.period.trialPhrase), then \(product.displayPrice) a \(product.period.phrase). " +
                "We remind you 2 days before it ends. \(renewal)"
        }
        return "\(product.displayPrice) a \(product.period.phrase). \(renewal)"
    }

    func subtitle(for product: PaywallProduct) -> String {
        if let perMonth = product.displayPricePerMonth, product.period.unit == .year {
            return "\(perMonth) a month, billed yearly"
        }
        return "Billed every \(product.period.phrase)"
    }

    func badge(for product: PaywallProduct) -> String? {
        product.trial.map { "\($0.period.trialPhrase) free" }
    }

    var isBusy: Bool { isPurchasing || isRestoring }

    func purchase() async {
        guard !isBusy, selectedProduct != nil else { return }
        // trial_started / subscription_purchased come from the RevenueCat integration, not from here.
        analytics.track(.purchaseStarted(plan: selectedPlan.rawValue))
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchases.purchase(selectedPlan) {
            case .purchased(let entitlement) where entitlement.isPremium:
                appState.activateSubscription(entitlement.plan ?? selectedPlan)
                onFinish?()
            case .purchased:
                alertMessage = "The purchase went through but access isn’t active yet. Try Restore in a moment."
            case .cancelled:
                break
            case .pending:
                alertMessage = "Your purchase is waiting for approval. Dreamer unlocks as soon as it’s approved."
            }
        } catch {
            alertMessage = "The purchase didn’t go through. Please try again."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let entitlement = try await purchases.restore()
            if entitlement.isPremium {
                appState.activateSubscription(entitlement.plan ?? .yearly)
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
