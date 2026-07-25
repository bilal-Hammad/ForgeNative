import Foundation

/// The single boundary premium-feature checks go through (APP_REDESIGN_SPEC.md
/// §10: "gate premium-section visibility through the same repository-pattern
/// boundary... so entitlement checks are centralized rather than scattered
/// across views"). §10's actual StoreKit 2 purchase/entitlement flow is
/// Phase 4+ — this protocol is the architecture that flow will drop behind
/// later, matching the same "resolved during Phase 3: only the data-model
/// tier flag exists so far" pattern §10 already used for premium suggested
/// sections.
///
/// Async, not a plain `Bool` property, on purpose — a real StoreKit 2
/// implementation needs to check `Transaction.currentEntitlements` (an
/// async sequence), so the boundary is shaped for that from the start
/// rather than needing every call site to change later.
protocol EntitlementService: Sendable {
    /// Whether the current user has an active premium entitlement — gates
    /// Progress's "Best Day/Time & Streak Distribution" card (this pass)
    /// and, per §10, premium suggested sections (not yet wired to this
    /// boundary — that gate still reads its own `SuggestedSectionTier` flag
    /// directly; consolidating it behind this same protocol is a
    /// reasonable follow-up, not attempted here to keep this pass scoped to
    /// what was actually asked for).
    func isPremiumUnlocked() async -> Bool
}

/// Stub implementation — always locked. This is intentionally the only
/// implementation that exists right now; real StoreKit 2 `Transaction`/
/// `Product` wiring is Phase 4+ per §10, alongside the other "sensitive
/// integrations" (Calendar/Reminders/Notifications/HealthKit).
struct StubEntitlementService: EntitlementService {
    func isPremiumUnlocked() async -> Bool { false }
}
