import Foundation
import os
@preconcurrency import RevenueCat

/// Subscriptions through RevenueCat (StoreKit 2 underneath). Access is the `premium` entitlement;
/// the app user id is the backend user id after sign-in, so the backend's RevenueCat webhook and
/// premium checks see the same customer.
struct RevenueCatPurchaseService: PurchaseService {
    static let entitlementID = "premium"

    /// The backend user id purchases must belong to: set at sign-in and for a session restored at
    /// launch, cleared at sign-out. The server finds the account only by this id; a purchase made
    /// by RevenueCat's anonymous `$RCAnonymousID` would unlock premium for nobody.
    private static let account = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// Configures the SDK once: with the stored user id when a session survives the relaunch, so
    /// the root paywall never starts anonymous; anonymous otherwise, until `logIn`.
    init(apiKey: String, debugLogs: Bool, appUserID: String? = nil) {
        if !Purchases.isConfigured {
            Self.account.withLock { $0 = appUserID }
            Purchases.logLevel = debugLogs ? .debug : .warn
            Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey)
                .with(appUserID: appUserID)
                .with(storeKitVersion: .storeKit2)
                .build())
        }
    }

    /// Purchases and restores happen as the signed-in account. `logIn` runs in the background at
    /// sign-in and its failure (no network) was silent, so a quick tap on the paywall could buy as
    /// the anonymous id: the link is checked, and made, before the store is asked.
    private func ensureLinked() async throws {
        guard let userID = Self.account.withLock({ $0 }) else { throw PurchaseError.accountNotLinked }
        if Purchases.shared.appUserID == userID { return }
        do {
            _ = try await Purchases.shared.logIn(userID)
        } catch {
            throw PurchaseError.accountNotLinked
        }
        guard Purchases.shared.appUserID == userID else { throw PurchaseError.accountNotLinked }
    }

    func products() async throws -> [PaywallProduct] {
        let packages = try await currentPackages()
        var result: [PaywallProduct] = []
        for package in packages {
            let product = package.storeProduct
            guard let plan = Self.plan(for: package), let rcPeriod = product.subscriptionPeriod else { continue }
            let period = PaywallProduct.Period(rcPeriod)
            var trial: PaywallProduct.Trial?
            if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
                let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
                if eligibility == .eligible {
                    trial = PaywallProduct.Trial(period: PaywallProduct.Period(intro.subscriptionPeriod))
                }
            }
            let locale = product.priceFormatter?.locale ?? .current
            result.append(PaywallProduct(
                plan: plan, productID: product.productIdentifier, displayPrice: product.localizedPriceString,
                price: product.price, currencyCode: product.currencyCode, period: period,
                displayPricePerMonth: PaywallProduct.perMonth(price: product.price, period: period, locale: locale,
                                                              currencyCode: product.currencyCode),
                trial: trial))
        }
        return result.sorted { $0.plan == .yearly && $1.plan != .yearly }
    }

    func purchase(_ plan: Plan) async throws -> PurchaseOutcome {
        try await ensureLinked()
        guard let package = try await currentPackages().first(where: { Self.plan(for: $0) == plan }) else {
            throw PurchaseError.productNotFound
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            return .purchased(Self.entitlement(from: result.customerInfo))
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        } catch let error as ErrorCode where error == .paymentPendingError {
            return .pending
        } catch let error as ErrorCode where error == .purchaseNotAllowedError {
            throw PurchaseError.notAllowed
        }
    }

    func restore() async throws -> EntitlementState {
        try await ensureLinked()
        return Self.entitlement(from: try await Purchases.shared.restorePurchases())
    }

    func entitlementUpdates() -> AsyncStream<EntitlementState> {
        AsyncStream { continuation in
            let task = Task {
                // The stream starts with the cached customer info, then follows every change.
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(Self.entitlement(from: info))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A failure here (no network) is retried by `ensureLinked` before the next purchase.
    func logIn(userID: String) async {
        Self.account.withLock { $0 = userID }
        _ = try? await Purchases.shared.logIn(userID)
    }

    /// `$appsflyerId` / `$adjustId`, so RevenueCat's MMP integration can attribute trial_start and
    /// purchase.
    func setAttribution(_ id: AttributionID) {
        switch id {
        case .appsFlyer(let value): Purchases.shared.attribution.setAppsflyerID(value)
        case .adjust(let value): Purchases.shared.attribution.setAdjustID(value)
        }
    }

    /// Only after the tracking answer: asked before it, the IDFA would be empty for good.
    func collectDeviceIdentifiers() {
        Purchases.shared.attribution.collectDeviceIdentifiers()
    }

    func logOut() async {
        Self.account.withLock { $0 = nil }
        guard !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }

    /// The backend's offering is "dreamer" ($rc_annual, $rc_weekly); `current` covers a dashboard
    /// where it is not named that.
    static let offeringID = "dreamer"

    private func currentPackages() async throws -> [Package] {
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.offering(identifier: Self.offeringID) ?? offerings.current else {
            throw PurchaseError.storeUnavailable
        }
        return offering.availablePackages
    }

    /// By the package type first, so the App Store product ids may be anything; the product id is the
    /// fallback for custom packages.
    static func plan(for package: Package) -> Plan? {
        plan(packageType: package.packageType) ?? Plan(productID: package.storeProduct.productIdentifier)
    }

    static func plan(packageType: PackageType) -> Plan? {
        switch packageType {
        case .annual: .yearly
        case .weekly: .weekly
        default: nil
        }
    }

    static func entitlement(from info: CustomerInfo) -> EntitlementState {
        guard let premium = info.entitlements[entitlementID], premium.isActive else { return .none }
        return EntitlementState(isPremium: true, plan: Plan(productID: premium.productIdentifier),
                                expiresAt: premium.expirationDate, willRenew: premium.willRenew,
                                isTrial: premium.periodType == .trial)
    }
}

private extension PaywallProduct.Period {
    init(_ period: SubscriptionPeriod) {
        let unit: PaywallProduct.PeriodUnit = switch period.unit {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
        self.init(value: period.value, unit: unit)
    }
}
