import Foundation
import StoreKit

/// Subscriptions straight through StoreKit 2. Used when the build has no RevenueCat key: with the
/// local `StoreKit/Dreamer.storekit` configuration (scheme Run option) purchases work in the
/// simulator without App Store Connect or sandbox accounts. Production uses RevenueCat.
struct StoreKitPurchaseService: PurchaseService {
    func products() async throws -> [PaywallProduct] {
        let products = try await Product.products(for: Plan.allCases.map(\.productID))
        var result: [PaywallProduct] = []
        for product in products {
            guard let plan = Plan(productID: product.id), let subscription = product.subscription else { continue }
            let period = PaywallProduct.Period(subscription.subscriptionPeriod)
            let currency = product.priceFormatStyle.currencyCode
            var trial: PaywallProduct.Trial?
            if let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial,
               await subscription.isEligibleForIntroOffer {
                trial = PaywallProduct.Trial(period: PaywallProduct.Period(offer.period))
            }
            result.append(PaywallProduct(
                plan: plan, productID: product.id, displayPrice: product.displayPrice, price: product.price,
                currencyCode: currency, period: period,
                displayPricePerMonth: PaywallProduct.perMonth(price: product.price, period: period,
                                                              locale: product.priceFormatStyle.locale, currencyCode: currency),
                trial: trial))
        }
        return result.sorted { $0.plan == .yearly && $1.plan != .yearly }
    }

    func purchase(_ plan: Plan) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [plan.productID]).first else { throw PurchaseError.productNotFound }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try Self.verified(verification)
            await transaction.finish()
            return .purchased(await Self.currentEntitlement())
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restore() async throws -> EntitlementState {
        try await AppStore.sync()
        return await Self.currentEntitlement()
    }

    func entitlementUpdates() -> AsyncStream<EntitlementState> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(await Self.currentEntitlement())
                // Renewals, expiries, refunds and purchases made on other devices.
                for await update in Transaction.updates {
                    if let transaction = try? Self.verified(update) { await transaction.finish() }
                    continuation.yield(await Self.currentEntitlement())
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // StoreKit alone has no account: the backend learns about purchases through RevenueCat only.
    func logIn(userID: String) async {}
    func logOut() async {}

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw PurchaseError.notAllowed
        }
    }

    static func currentEntitlement(now: Date = .now) async -> EntitlementState {
        var best: EntitlementState = .none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, let plan = Plan(productID: transaction.productID) else { continue }
            if let expiry = transaction.expirationDate, expiry < now { continue }
            let willRenew = await transaction.subscriptionStatus?.state == .subscribed
            if !best.isPremium || (transaction.expirationDate ?? .distantFuture) > (best.expiresAt ?? .distantPast) {
                best = EntitlementState(isPremium: true, plan: plan, expiresAt: transaction.expirationDate, willRenew: willRenew)
            }
        }
        return best
    }
}

extension Plan {
    init?(productID: String) {
        guard let plan = Plan.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }
}

private extension PaywallProduct.Period {
    init(_ period: Product.SubscriptionPeriod) {
        let unit: PaywallProduct.PeriodUnit = switch period.unit {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        @unknown default: .month
        }
        self.init(value: period.value, unit: unit)
    }
}
