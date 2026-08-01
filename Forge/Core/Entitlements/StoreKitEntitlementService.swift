import Foundation
import StoreKit

/// Real StoreKit 2 entitlement + purchase boundary (P1 "StoreKit + Islamic
/// Template"). Conforms to `EntitlementService` for the read-only gating the
/// rest of the app does, and additionally exposes product listing / purchase
/// / restore for the paywall (Phase 8).
///
/// API surface verified against current StoreKit 2 (Aug 2026) before writing,
/// per the standing "verify APIs, don't assume" rule:
/// - `Product.products(for:)` loads products.
/// - `product.purchase()` returns `Product.PurchaseResult`
///   (`.success(VerificationResult<Transaction>)` / `.userCancelled` /
///   `.pending`).
/// - `Transaction.currentEntitlements` is the authoritative set of active
///   entitlements (subscriptions + non-consumables), kept correct across
///   devices — so a separate "restore" is mostly a `AppStore.sync()` nudge
///   followed by re-reading it.
/// - `Transaction.updates` streams post-launch changes (renewals, refunds,
///   Ask-to-Buy approvals, purchases made on another device).
/// - `VerificationResult` is unwrapped via the canonical `checkVerified`
///   switch (`.verified` / `.unverified`) rather than `payloadValue`, so an
///   unverified transaction is never trusted.
///
/// `@MainActor @Observable` so the paywall can bind to `products` /
/// `purchasedProductIDs` reactively; the gating reads (`isPremiumUnlocked` /
/// `isPackUnlocked`) each re-scan `currentEntitlements` for freshness rather
/// than trusting a possibly-stale cached snapshot.
@MainActor
@Observable
final class StoreKitEntitlementService: EntitlementService {
    /// Loaded products for the paywall (Phase 8). Empty until `loadProducts()`.
    private(set) var products: [Product] = []

    /// Product ids the user currently owns (subscriptions + non-consumables).
    /// Reactive so paywall UI updates the instant an entitlement changes.
    private(set) var purchasedProductIDs: Set<String> = []

    /// Long-lived listener for out-of-band transaction changes. Held so it
    /// isn't discarded; intentionally never cancelled — this service is an
    /// app-lifetime singleton (constructed once in `ForgeApp.init()`), and
    /// the listener must stay alive the whole time to catch renewals /
    /// refunds / cross-device purchases. (No `deinit` cancel: the object
    /// never deinits, and a nonisolated `deinit` can't touch this MainActor
    /// property under Swift 6 strict concurrency anyway.)
    private var updatesListener: Task<Void, Never>?

    init() {
        // Start listening before the initial scan so a change that lands
        // mid-launch isn't missed.
        updatesListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                await self.handle(update)
            }
        }
        Task { await refreshOwnedProductIDs() }
    }

    // MARK: - EntitlementService (read-only gating boundary)

    func isPremiumUnlocked() async -> Bool {
        let owned = await refreshOwnedProductIDs()
        return EntitlementResolver.isPremiumUnlocked(ownedProductIDs: owned)
    }

    func isPackUnlocked(_ packID: String) async -> Bool {
        let owned = await refreshOwnedProductIDs()
        return EntitlementResolver.isPackUnlocked(packID, ownedProductIDs: owned)
    }

    // MARK: - Storefront (paywall — Phase 8)

    /// Loads product metadata (localized title, `displayPrice`, subscription
    /// period). Prices are always rendered from `product.displayPrice`, never
    /// hardcoded, so App Store Connect price changes need no app update.
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductIdentifiers.all)
            // Stable order: subscriptions first, then packs, by price.
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // Non-fatal — a transient StoreKit/network failure leaves the
            // last-known products in place; the paywall handles an empty
            // list gracefully (Phase 8).
        }
    }

    /// Runs the system purchase sheet. Returns `true` only on a verified
    /// successful purchase (entitlements refreshed + transaction finished),
    /// `false` for user-cancel / pending (Ask-to-Buy). Throws on a StoreKit
    /// error or an unverified transaction.
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await refreshOwnedProductIDs()
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Restore: `Transaction.currentEntitlements` already reflects everything
    /// the account owns, so this just forces a sync then re-scans. Exposed
    /// for an explicit "Restore Purchases" button (App Review requires one).
    func restore() async {
        try? await AppStore.sync()
        await refreshOwnedProductIDs()
    }

    // MARK: - Internal

    /// Re-scan `currentEntitlements`, update the reactive set, and return it.
    @discardableResult
    private func refreshOwnedProductIDs() async -> Set<String> {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            // A revoked (refunded/family-removed) transaction is still listed
            // but no longer entitles anything.
            guard transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
        return owned
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await refreshOwnedProductIDs()
        await transaction.finish()
    }

    /// Canonical StoreKit 2 verification unwrap — never trust an unverified
    /// transaction (fails closed).
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
