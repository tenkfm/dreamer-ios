import Foundation
import StoreKitTest
import Testing
@testable import Dreamer

/// Purchases against the local StoreKit configuration (StoreKit/Dreamer.storekit), no App Store needed.
/// Opt-in (`TEST_RUNNER_DREAMER_STOREKIT_TESTS=1`, or run from Xcode): on the Xcode 26.2 / iOS 26.3
/// simulator driven from the command line, SKTestSession serves no products at all - not even
/// RevenueCat's reference configuration - so CI cannot run these.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DREAMER_STOREKIT_TESTS"] == "1"))
struct StoreKitPurchaseTests {
    private static var configuration: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "StoreKit/Dreamer.storekit")
    }

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf: Self.configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    @Test func productsHaveLocalizedPricesAndTheTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let products = try await StoreKitPurchaseService().products()

        #expect(products.map(\.plan) == [.yearly, .weekly])
        let yearly = try #require(products.first)
        #expect(yearly.displayPrice == "$39.99")
        #expect(yearly.displayPricePerMonth == "$3.33")
        #expect(yearly.trial?.period.trialPhrase == "7 days")
        #expect(yearly.period == .init(value: 1, unit: .year))
        #expect(products.last?.trial == nil)
    }

    @Test func purchaseInTheSimulatorGrantsAccess() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: true)
        let viewModel = PaywallViewModel(purchases: StoreKitPurchaseService(), appState: appState)

        viewModel.selectedPlan = .weekly
        await viewModel.purchase()

        #expect(viewModel.alertMessage == nil)
        #expect(viewModel.haptic?.kind == .success)
        #expect(appState.subscription == .active(.weekly))
        #expect(appState.rootScreen == .main)
        #expect(await StoreKitPurchaseService.currentEntitlement().isPremium)
    }

    @Test func usedTrialIsNotOfferedAgain() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        _ = try await StoreKitPurchaseService().purchase(.yearly)
        try session.expireSubscription(productIdentifier: Plan.yearly.productID)

        let yearly = try await StoreKitPurchaseService().products().first { $0.plan == .yearly }
        #expect(yearly?.trial == nil)
    }
}

struct PricePerMonthTests {
    @Test func yearlyPriceIsShownPerMonthInTheStoreCurrency() {
        let year = PaywallProduct.Period(value: 1, unit: .year)
        #expect(PaywallProduct.perMonth(price: 39.99, period: year, locale: Locale(identifier: "en_US"), currencyCode: "USD") == "$3.33")
        #expect(PaywallProduct.perMonth(price: 34.99, period: year, locale: Locale(identifier: "en_GB"), currencyCode: "GBP") == "£2.91")
        let euro = PaywallProduct.perMonth(price: 39.99, period: year, locale: Locale(identifier: "de_DE"), currencyCode: "EUR")
        #expect(euro?.replacingOccurrences(of: "\u{00A0}", with: " ") == "3,33 €")
    }

    @Test func shortPlansHaveNoMonthlyPrice() {
        #expect(PaywallProduct.perMonth(price: 6.99, period: .init(value: 1, unit: .week), locale: .current, currencyCode: "USD") == nil)
        #expect(PaywallProduct.perMonth(price: 9.99, period: .init(value: 1, unit: .month), locale: .current, currencyCode: "USD") == nil)
    }

    @Test func trialsReadInDays() {
        #expect(PaywallProduct.Period(value: 1, unit: .week).trialPhrase == "7 days")
        #expect(PaywallProduct.Period(value: 3, unit: .day).trialPhrase == "3 days")
        #expect(PaywallProduct.Period(value: 1, unit: .month).trialPhrase == "1 month")
    }
}
