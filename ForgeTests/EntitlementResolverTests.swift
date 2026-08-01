import XCTest
@testable import Forge

/// Unit tests for the pure entitlement-resolution logic (P1 "StoreKit +
/// Islamic Template"). This is the genuinely automatable part of the
/// entitlement system — the live purchase/restore flow needs a system
/// purchase sheet + a sandbox account, which no automated run in this
/// environment can drive, so those are verified on Bilal's device (Phase 9).
/// Here we feed `EntitlementResolver` hand-built "owned product id" sets and
/// assert the premium/pack decisions, covering every ownership shape the real
/// `Transaction.currentEntitlements` scan can produce.
final class EntitlementResolverTests: XCTestCase {

    func testNothingOwnedLocksEverything() {
        let owned: Set<String> = []
        XCTAssertFalse(EntitlementResolver.isPremiumUnlocked(ownedProductIDs: owned))
        XCTAssertFalse(EntitlementResolver.isPackUnlocked("islamic", ownedProductIDs: owned))
    }

    func testMonthlySubscriptionUnlocksPremiumAndAllPacks() {
        let owned: Set<String> = [ProductIdentifiers.premiumMonthly]
        XCTAssertTrue(EntitlementResolver.isPremiumUnlocked(ownedProductIDs: owned))
        XCTAssertTrue(EntitlementResolver.isPackUnlocked("islamic", ownedProductIDs: owned))
    }

    func testYearlySubscriptionUnlocksPremiumAndAllPacks() {
        let owned: Set<String> = [ProductIdentifiers.premiumYearly]
        XCTAssertTrue(EntitlementResolver.isPremiumUnlocked(ownedProductIDs: owned))
        XCTAssertTrue(EntitlementResolver.isPackUnlocked("islamic", ownedProductIDs: owned))
    }

    func testOwningOnlyThePackUnlocksThatPackButNotPremium() {
        let owned: Set<String> = [ProductIdentifiers.islamicPack]
        // Owning the standalone pack must NOT report generic premium as
        // unlocked (that would wrongly hand over every other premium feature).
        XCTAssertFalse(EntitlementResolver.isPremiumUnlocked(ownedProductIDs: owned))
        XCTAssertTrue(EntitlementResolver.isPackUnlocked("islamic", ownedProductIDs: owned))
    }

    func testPackIdAliasResolvesToSameProduct() {
        // Both the bare pack id and the catalog section id map to the Islamic
        // non-consumable, so gating either way is consistent.
        let owned: Set<String> = [ProductIdentifiers.islamicPack]
        XCTAssertTrue(EntitlementResolver.isPackUnlocked("islamic", ownedProductIDs: owned))
        XCTAssertTrue(EntitlementResolver.isPackUnlocked("good-islamic", ownedProductIDs: owned))
    }

    func testUnknownPackIsLockedWithoutPremium() {
        let owned: Set<String> = [ProductIdentifiers.islamicPack]
        // A pack with no standalone product id (subscription-only) is locked
        // unless premium is active.
        XCTAssertFalse(EntitlementResolver.isPackUnlocked("nonexistent-pack", ownedProductIDs: owned))
    }

    func testUnknownPackUnlockedByPremium() {
        let owned: Set<String> = [ProductIdentifiers.premiumYearly]
        XCTAssertTrue(EntitlementResolver.isPackUnlocked("nonexistent-pack", ownedProductIDs: owned))
    }

    func testUnrelatedProductDoesNotUnlockAnything() {
        let owned: Set<String> = ["com.some.other.product"]
        XCTAssertFalse(EntitlementResolver.isPremiumUnlocked(ownedProductIDs: owned))
        XCTAssertFalse(EntitlementResolver.isPackUnlocked("islamic", ownedProductIDs: owned))
    }
}
