import Foundation

/// Pure entitlement resolution: given the set of product identifiers the
/// user currently owns (from StoreKit's `Transaction.currentEntitlements`),
/// decide whether premium is unlocked and whether a specific pack is
/// unlocked. Deliberately free of any StoreKit type so it's unit-testable
/// without a live store / `SKTestSession` — `StoreKitEntitlementService`
/// feeds it the live owned-set, tests feed it a hand-built one.
///
/// Rule (TASKS.md "P1 — StoreKit + Islamic Template"): premium = an active
/// subscription; a pack is unlocked if premium is active **or** the pack's
/// own non-consumable is owned.
enum EntitlementResolver {
    static func isPremiumUnlocked(ownedProductIDs: Set<String>) -> Bool {
        !ownedProductIDs.isDisjoint(with: ProductIdentifiers.subscriptions)
    }

    static func isPackUnlocked(_ packID: String, ownedProductIDs: Set<String>) -> Bool {
        if isPremiumUnlocked(ownedProductIDs: ownedProductIDs) { return true }
        guard let productID = ProductIdentifiers.packProductID(for: packID) else { return false }
        return ownedProductIDs.contains(productID)
    }
}
