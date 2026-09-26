import Foundation
import os
import Testing
@testable import Dreamer

/// Purchases that record the attribution id they get.
final class SpyPurchases: PurchaseService, @unchecked Sendable {
    private let base = MockPurchaseService()
    private let ids = OSAllocatedUnfairLock<[AttributionID]>(initialState: [])
    var attributionIDs: [AttributionID] { ids.withLock { $0 } }

    func products() async throws -> [PaywallProduct] { try await base.products() }
    func purchase(_ plan: Plan) async throws -> PurchaseOutcome { try await base.purchase(plan) }
    func restore() async throws -> EntitlementState { try await base.restore() }
    func entitlementUpdates() -> AsyncStream<EntitlementState> { base.entitlementUpdates() }
    func logIn(userID: String) async {}
    func logOut() async {}
    func setAttribution(_ id: AttributionID) { ids.withLock { $0.append(id) } }
}

@MainActor
struct AttributionTests {
    private func dependencies(attribution: RecordingAttribution, purchases: SpyPurchases) -> AppDependencies {
        AppDependencies(dreamStore: InMemoryDreamStore(), analysis: MockDreamAnalysisService(), purchases: purchases,
                        catalog: MockSymbolCatalog(), imageSaver: MockImageSaver(), attribution: attribution,
                        makeSpeechService: { MockSpeechService() }, makeReadAloudService: { MockReadAloudService() })
    }

    @Test func signingInNamesTheUserAndLinksTheMMPToRevenueCat() async {
        let attribution = RecordingAttribution(id: .appsFlyer("1700000000000-1234567"))
        let purchases = SpyPurchases()
        await dependencies(attribution: attribution, purchases: purchases).linkAccount(userID: "user-1")

        #expect(attribution.userIDs == ["user-1"])
        #expect(purchases.attributionIDs == [.appsFlyer("1700000000000-1234567")])
    }

    @Test func signingOutForgetsTheUser() async {
        let attribution = RecordingAttribution()
        let purchases = SpyPurchases()
        await dependencies(attribution: attribution, purchases: purchases).unlinkAccount()
        #expect(attribution.userIDs == [nil])
        #expect(purchases.attributionIDs.isEmpty)
    }
}
