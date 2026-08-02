import XCTest
import StoreKit
import StoreKitTest
@testable import Forge

/// On-device StoreKit entitlement verification (P1 Phase 9 — the automatable
/// half of "StoreKit sandbox left for Bilal"). Where `EntitlementResolverTests`
/// checks the pure resolution rule against hand-built owned-sets, these drive
/// **real StoreKit 2 transactions** through the actual `StoreKitEntitlementService`
/// — `SKTestSession.buyProduct` injects a genuine `Transaction`, the service
/// reads it back via `Transaction.currentEntitlements`, and the gating methods
/// resolve against it. That closes the "does entitlement resolution wire
/// correctly end-to-end through the transaction machinery" question on real
/// hardware, without needing a Sandbox Apple ID.
///
/// It does **not** exercise Apple's system purchase sheet / Face-ID
/// authentication (out-of-process, human-only) — that residue stays a manual
/// device pass. `SKTestSession.disableDialogs = true` deliberately bypasses
/// the confirm sheet so the transaction is injected directly.
///
/// API verified against the installed StoreKitTest SDK (iOS 26.5) before
/// writing: `init(configurationFileNamed:) throws`, `disableDialogs`,
/// `clearTransactions()`, `buyProduct(identifier:options:) async throws`.
/// The `.storekit` config is bundled into this test target as a resource
/// (see project.yml).
@MainActor
final class StoreKitEntitlementServiceTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "Forge")
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
    }

    /// Buying the auto-renewable subscription unlocks premium **and** every
    /// pack, including the Islamic pack, with no standalone pack purchase.
    func testSubscriptionUnlocksEverythingIncludingIslamicPack() async throws {
        _ = try await session.buyProduct(identifier: ProductIdentifiers.premiumMonthly)
        let service = StoreKitEntitlementService()

        try await assertEventually { await service.isPremiumUnlocked() }
        try await assertEventually { await service.isPackUnlocked("islamic") }
        // A catalog section id (not the bare pack id) must resolve the same way.
        try await assertEventually { await service.isPackUnlocked("good-islamic-prayers") }
    }

    /// Buying the Islamic pack standalone unlocks *only* that pack — premium
    /// features stay locked, and no subscription is implied.
    func testIslamicPackStandaloneUnlocksOnlyThatPack() async throws {
        _ = try await session.buyProduct(identifier: ProductIdentifiers.islamicPack)
        let service = StoreKitEntitlementService()

        try await assertEventually { await service.isPackUnlocked("islamic") }
        // Premium must NOT unlock from a one-off pack purchase.
        let premium = await service.isPremiumUnlocked()
        XCTAssertFalse(premium, "A standalone pack purchase must not unlock premium features")
    }

    /// A fresh service instance (relaunch/logout has no local entitlement
    /// storage — the service always re-scans `currentEntitlements`) plus an
    /// explicit `restore()` re-applies an owned subscription. This mirrors the
    /// "Restore Purchases" button path: `AppStore.sync()` then re-scan.
    func testRestoreReappliesOwnedSubscription() async throws {
        _ = try await session.buyProduct(identifier: ProductIdentifiers.premiumYearly)

        // Simulate a fresh launch: a brand-new service with zero cached state.
        let freshService = StoreKitEntitlementService()
        await freshService.restore()

        try await assertEventually { await freshService.isPremiumUnlocked() }
        try await assertEventually { await freshService.isPackUnlocked("islamic") }
    }

    /// With nothing purchased, everything premium-gated stays locked.
    func testNothingUnlockedWhenNoPurchases() async throws {
        let service = StoreKitEntitlementService()
        let premium = await service.isPremiumUnlocked()
        let islamic = await service.isPackUnlocked("islamic")
        XCTAssertFalse(premium)
        XCTAssertFalse(islamic)
    }

    // MARK: - Helpers

    /// Polls an async boolean up to `attempts` times, allowing a beat for a
    /// freshly-injected transaction to propagate into `currentEntitlements`
    /// before asserting. Fails if it never becomes true.
    private func assertEventually(
        attempts: Int = 20,
        _ condition: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        XCTFail("Condition never became true after \(attempts) attempts", file: file, line: line)
    }
}
