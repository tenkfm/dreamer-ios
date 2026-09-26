import Foundation
@preconcurrency import RevenueCat

/// Subscriptions through RevenueCat (StoreKit 2 underneath). Access is the `premium` entitlement;
/// the app user id is the backend user id after sign-in, so the backend's RevenueCat webhook and
/// premium checks see the same customer.
struct RevenueCatPurchaseService: PurchaseService {
    static let entitlementID = "premium"

    /// Configures the SDK once, anonymous until `logIn`.
    init(apiKey: String, debugLogs: Bool) {
        if !Purchases.isConfigured {
            Purchases.logLevel = debugLogs ? .debug : .warn
            Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey)
                .with(storeKitVersion: .storeKit2)
                .build())
        }
    }

    func products() async throws -> [PaywallProduct] {
        let packages = try await currentPackages()
        var result: [PaywallProduct] = []
        for package in packages {
            let product = package.storeProduct
            guard let plan = Plan(productID: product.productIdentifier), let rcPeriod = product.subscriptionPeriod else { continue }
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
        guard let package = try await currentPackages().first(where: { $0.storeProduct.productIdentifier == plan.productID }) else {
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
        Self.entitlement(from: try await Purchases.shared.restorePurchases())
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

    func logIn(userID: String) async {
        _ = try? await Purchases.shared.logIn(userID)
    }

    /// `$appsflyerId` / `$adjustId` plus the device identifiers (IDFA only with tracking allowed),
    /// so RevenueCat's MMP integration can attribute trial_start and purchase.
    func setAttribution(_ id: AttributionID) {
        switch id {
        case .appsFlyer(let value): Purchases.shared.attribution.setAppsflyerID(value)
        case .adjust(let value): Purchases.shared.attribution.setAdjustID(value)
        }
        Purchases.shared.attribution.collectDeviceIdentifiers()
    }

    func logOut() async {
        guard !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }

    private func currentPackages() async throws -> [Package] {
        guard let offering = try await Purchases.shared.offerings().current else { throw PurchaseError.storeUnavailable }
        return offering.availablePackages
    }

    static func entitlement(from info: CustomerInfo) -> EntitlementState {
        guard let premium = info.entitlements[entitlementID], premium.isActive else { return .none }
        return EntitlementState(isPremium: true, plan: Plan(productID: premium.productIdentifier),
                                expiresAt: premium.expirationDate, willRenew: premium.willRenew)
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
