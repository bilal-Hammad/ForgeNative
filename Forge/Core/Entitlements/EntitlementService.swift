import Foundation

/// The single boundary premium-feature checks go through (APP_REDESIGN_SPEC.md
/// §10: "gate premium-section visibility through the same repository-pattern
/// boundary... so entitlement checks are centralized rather than scattered
/// across views"). As of the P1 "StoreKit + Islamic Template" initiative the
/// real StoreKit 2 implementation (`StoreKitEntitlementService`) lives behind
/// this protocol; `StubEntitlementService` remains the previews/tests default.
///
/// Async, not a plain `Bool` property, on purpose — the real StoreKit 2
/// implementation checks `Transaction.currentEntitlements` (an async
/// sequence), so the boundary is shaped for that.
protocol EntitlementService: Sendable {
    /// Whether the current user has an active **Forge Premium** subscription
    /// — gates every generic-premium feature (Progress's "Best Day/Time &
    /// Streak Distribution" card, `.premium`-tier suggested sections, etc.).
    func isPremiumUnlocked() async -> Bool

    /// Whether a specific template pack is unlocked — true if the user has
    /// premium **or** owns that pack's standalone non-consumable. `packID`
    /// is a `TemplateSection`/pack id (see `ProductIdentifiers.packProductID`).
    func isPackUnlocked(_ packID: String) async -> Bool
}

/// Stub — locked by default. Kept as the previews/tests default (the
/// environment's `defaultValue`) and as the `-uiTesting` fixture's
/// entitlement source. `premiumOverride` lets a UI test launch with
/// everything unlocked (the `-premiumUnlocked` launch argument, see
/// `ForgeApp`) so entitlement *gating* can be exercised both ways without a
/// live App Store / sandbox account, which no automated run in this
/// environment has.
struct StubEntitlementService: EntitlementService {
    var premiumOverride: Bool = false
    func isPremiumUnlocked() async -> Bool { premiumOverride }
    func isPackUnlocked(_ packID: String) async -> Bool { premiumOverride }
}
