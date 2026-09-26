import Foundation

/// A plan as the store sells it to this user: real, localized prices and the trial this user can get.
struct PaywallProduct: Sendable, Equatable, Identifiable {
    enum PeriodUnit: String, Sendable { case day, week, month, year }

    struct Period: Sendable, Equatable {
        var value: Int
        var unit: PeriodUnit
    }

    struct Trial: Sendable, Equatable {
        var period: Period
    }

    var plan: Plan
    var productID: String
    /// "$39.99", "£34.99", "39,99 €"
    var displayPrice: String
    var price: Decimal
    var currencyCode: String?
    var period: Period
    /// Yearly price divided by 12, in the same currency ("$3.33"); nil for plans under a month.
    var displayPricePerMonth: String?
    /// Only when this user is still eligible for the introductory offer.
    var trial: Trial?

    var id: String { productID }
}

/// What the store says about the user's access.
struct EntitlementState: Sendable, Equatable {
    var isPremium: Bool
    var plan: Plan?
    var expiresAt: Date?
    var willRenew: Bool
    /// In the free trial: `expiresAt` is when it turns into the paid plan.
    var isTrial = false

    static let none = EntitlementState(isPremium: false, plan: nil, expiresAt: nil, willRenew: false)
}

enum PurchaseOutcome: Sendable, Equatable {
    case purchased(EntitlementState)
    /// The user closed the store sheet.
    case cancelled
    /// Ask to Buy or a delayed payment: access comes later through `entitlementUpdates`.
    case pending
}

enum PurchaseError: Error, Equatable {
    case productNotFound
    case notAllowed
    case storeUnavailable
    case failed(String)
}

extension PaywallProduct.Period {
    /// "year", "week", "7 days"
    var phrase: String {
        let unit = unit.rawValue
        return value == 1 ? unit : "\(value) \(unit)s"
    }

    /// "7 days", "1 week" -> "7 days" (trials read better in days).
    var trialPhrase: String {
        switch unit {
        case .day: "\(value) day\(value == 1 ? "" : "s")"
        case .week: "\(value * 7) days"
        case .month: "\(value) month\(value == 1 ? "" : "s")"
        case .year: "\(value) year\(value == 1 ? "" : "s")"
        }
    }
}

extension PaywallProduct {
    /// Price per month for a longer plan, formatted like the store price.
    static func perMonth(price: Decimal, period: Period, locale: Locale, currencyCode: String?) -> String? {
        let months: Decimal
        switch period.unit {
        case .year: months = Decimal(12 * period.value)
        case .month where period.value > 1: months = Decimal(period.value)
        default: return nil
        }
        var monthly = price / months
        var rounded = Decimal()
        NSDecimalRound(&rounded, &monthly, 2, .down)
        guard let currencyCode else { return nil }
        return rounded.formatted(.currency(code: currencyCode).locale(locale))
    }
}
