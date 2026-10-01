import RevenueCat
import Testing
@testable import Dreamer

struct RevenueCatMappingTests {
    /// The backend's offering "dreamer" carries $rc_annual and $rc_weekly: the plan comes from the
    /// package type, whatever the App Store product ids are.
    @Test func plansComeFromThePackageType() {
        #expect(RevenueCatPurchaseService.offeringID == "dreamer")
        #expect(RevenueCatPurchaseService.plan(packageType: .annual) == .yearly)
        #expect(RevenueCatPurchaseService.plan(packageType: .weekly) == .weekly)
        #expect(RevenueCatPurchaseService.plan(packageType: .monthly) == nil)
        #expect(RevenueCatPurchaseService.plan(packageType: .custom) == nil)
    }
}
