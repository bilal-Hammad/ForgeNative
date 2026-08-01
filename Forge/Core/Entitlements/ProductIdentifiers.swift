import Foundation

/// The single source of truth for every StoreKit product identifier the app
/// sells, and the mapping from a template-pack id (e.g. `"islamic"`) to its
/// standalone non-consumable product. Centralized so the `.storekit` test
/// config, `StoreKitEntitlementService`, the paywall (Phase 8), and the
/// pack-gating logic all agree on the exact strings — a mismatch here is the
/// classic "products never load / entitlement never resolves" StoreKit bug.
///
/// Monetization model (TASKS.md "P1 — StoreKit + Islamic Template"): one
/// auto-renewable **subscription** ("Forge Premium", monthly + yearly) that
/// unlocks *everything*, plus each **template pack** also purchasable as a
/// one-time **non-consumable** for someone who wants just that pack. The
/// "premium OR owns this pack" resolution lives in `EntitlementResolver`.
enum ProductIdentifiers {
    // MARK: Subscription (unlocks all premium features + all packs)
    static let premiumMonthly = "com.bilalhammad.forge.native.premium.monthly"
    static let premiumYearly = "com.bilalhammad.forge.native.premium.yearly"

    // MARK: Template packs (standalone non-consumables)
    static let islamicPack = "com.bilalhammad.forge.native.pack.islamic"

    /// Any of these being owned means an active Forge Premium subscription →
    /// all premium features and all packs are unlocked.
    static let subscriptions: Set<String> = [premiumMonthly, premiumYearly]

    /// Standalone pack non-consumables.
    static let packs: Set<String> = [islamicPack]

    /// Every identifier to request from `Product.products(for:)`.
    static var all: [String] { Array(subscriptions) + Array(packs) }

    /// Maps a `TemplateSection`/pack id to its standalone non-consumable
    /// product id. Returns `nil` for a pack that isn't individually sold
    /// (so it's subscription-only). Kept as an explicit switch rather than a
    /// string-munging convention so a typo can't silently produce a wrong,
    /// never-owned identifier.
    static func packProductID(for packID: String) -> String? {
        // Every Islamic catalog section id is `good-islamic-*` (or the bare
        // `islamic`), all unlocked by the one Islamic Pack non-consumable.
        if packID == "islamic" || packID.hasPrefix("good-islamic") {
            return islamicPack
        }
        return nil
    }
}
