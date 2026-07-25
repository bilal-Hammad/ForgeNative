import Foundation

/// APP_REDESIGN_SPEC.md §10: suggested sections split into a free tier
/// (available to everyone) and a premium tier (unlocked via a StoreKit 2
/// subscription). Creating a fully custom section is always free regardless
/// of this enum — it only applies to the ready-made "suggested section"
/// catalog offered from the Edit-mode flow (§5).
///
/// The actual StoreKit 2 purchase/entitlement flow is deferred to Phase 4+
/// per §10 ("not before the core app is working," grouped with the other
/// sensitive integrations) — this enum only marks *which* sections will
/// eventually require an entitlement, so that data modeling doesn't need
/// rework once the real purchase flow lands.
enum SuggestedSectionTier: String, Codable {
    case free
    case premium
}
