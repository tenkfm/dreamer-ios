import Foundation
import Testing
@testable import Dreamer

@MainActor
struct PaywallCopyTests {
    private func loaded(_ purchases: any PurchaseService) async -> PaywallViewModel {
        let viewModel = PaywallViewModel(purchases: purchases, appState: AppState(store: InMemoryPreferencesStore()))
        await viewModel.loadProducts()
        return viewModel
    }

    @Test func yearlyWithTrialMatchesTheDesign() async throws {
        let viewModel = await loaded(MockPurchaseService(delay: .zero))
        let yearly = try #require(viewModel.selectedProduct)

        #expect(viewModel.ctaTitle == "Try 7 days free")
        #expect(viewModel.subtitle(for: yearly) == "$3.33 a month, billed yearly")
        #expect(viewModel.badge(for: yearly) == "7 days free")
        #expect(viewModel.termsText.hasPrefix("Free for 7 days, then $39.99 a year. We remind you 2 days before it ends."))
        #expect(viewModel.termsText.contains("Renews automatically until you cancel"))
    }

    @Test func everyPlansTermsAreKnownSoTheFooterKeepsItsHeight() async {
        let viewModel = await loaded(MockPurchaseService(delay: .zero))
        #expect(viewModel.allTermsTexts.count == viewModel.products.count)
        for plan in [Plan.yearly, .weekly] {
            viewModel.selectedPlan = plan
            #expect(viewModel.allTermsTexts.contains(viewModel.termsText))
        }
    }

    @Test func noTrialWhenTheUserIsNotEligible() async throws {
        let viewModel = await loaded(MockPurchaseService(delay: .zero, trialEligible: false))
        let yearly = try #require(viewModel.selectedProduct)

        #expect(viewModel.ctaTitle == "Subscribe for $39.99 a year")
        #expect(viewModel.badge(for: yearly) == nil)
        #expect(viewModel.termsText.hasPrefix("$39.99 a year. Renews automatically"))
    }

    @Test func weeklyCopy() async throws {
        let viewModel = await loaded(MockPurchaseService(delay: .zero))
        viewModel.selectedPlan = .weekly
        let weekly = try #require(viewModel.selectedProduct)

        #expect(viewModel.ctaTitle == "Subscribe for $6.99 a week")
        #expect(viewModel.subtitle(for: weekly) == "Billed every week")
    }

    @Test func localPricesComeFromTheStore() async throws {
        struct PoundStore: PurchaseService {
            func products() async throws -> [PaywallProduct] {
                [PaywallProduct(plan: .yearly, productID: "dreamer.yearly", displayPrice: "£34.99", price: 34.99, currencyCode: "GBP",
                                period: .init(value: 1, unit: .year),
                                displayPricePerMonth: PaywallProduct.perMonth(price: 34.99, period: .init(value: 1, unit: .year),
                                                                              locale: Locale(identifier: "en_GB"), currencyCode: "GBP"),
                                trial: .init(period: .init(value: 1, unit: .week)))]
            }
            func purchase(_ plan: Plan) async throws -> PurchaseOutcome { .cancelled }
            func restore() async throws -> EntitlementState { .none }
            func entitlementUpdates() -> AsyncStream<EntitlementState> { AsyncStream { $0.finish() } }
            func logIn(userID: String) async {}
            func logOut() async {}
        }
        let viewModel = await loaded(PoundStore())
        let yearly = try #require(viewModel.selectedProduct)

        #expect(viewModel.subtitle(for: yearly) == "£2.91 a month, billed yearly")
        #expect(viewModel.termsText.hasPrefix("Free for 7 days, then £34.99 a year."))
    }

    @Test func storeFailureShowsNoPricesAndBlocksBuying() async {
        struct DownStore: PurchaseService {
            func products() async throws -> [PaywallProduct] { throw PurchaseError.storeUnavailable }
            func purchase(_ plan: Plan) async throws -> PurchaseOutcome { Issue.record("Must not buy"); return .cancelled }
            func restore() async throws -> EntitlementState { .none }
            func entitlementUpdates() -> AsyncStream<EntitlementState> { AsyncStream { $0.finish() } }
            func logIn(userID: String) async {}
            func logOut() async {}
        }
        let viewModel = await loaded(DownStore())

        #expect(viewModel.productsState == .failed)
        #expect(viewModel.selectedProduct == nil)
        await viewModel.purchase()
    }

    @Test func cancelledPurchaseChangesNothing() async {
        struct CancellingStore: PurchaseService {
            func products() async throws -> [PaywallProduct] { try await MockPurchaseService().products() }
            func purchase(_ plan: Plan) async throws -> PurchaseOutcome { .cancelled }
            func restore() async throws -> EntitlementState { .none }
            func entitlementUpdates() -> AsyncStream<EntitlementState> { AsyncStream { $0.finish() } }
            func logIn(userID: String) async {}
            func logOut() async {}
        }
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = PaywallViewModel(purchases: CancellingStore(), appState: appState)
        await viewModel.loadProducts()
        await viewModel.purchase()

        #expect(appState.subscription == .none)
        #expect(viewModel.alertMessage == nil)
        // Cancelling is the user's choice, not an outcome to feel.
        #expect(viewModel.haptic == nil)
    }
}
