import Foundation

/// Storage for earned §11 Milestone badges and the §8 points ledger. Same
/// role as `HabitRepository`/`TemplateSectionRepository` — the only
/// interface `MilestoneEngine` and the Milestones screens talk to; concrete
/// storage is swappable behind it.
protocol MilestoneRepository: Sendable {
    func fetchAll() async throws -> [Milestone]
    /// Most-recently-earned badges first — backs Progress's Milestones card
    /// preview strip.
    func fetchRecent(limit: Int) async throws -> [Milestone]
    /// Awards a badge unless one with the same `dedupeKey` already exists,
    /// in which case this is a no-op. Returns whether it was newly awarded
    /// (callers use this to know whether to show a "new badge" moment).
    @discardableResult
    func award(_ milestone: Milestone) async throws -> Bool

    /// Removes a previously-awarded badge by its `dedupeKey`, a no-op if
    /// none exists. Self-healing counterpart to `award` — used when a
    /// habit-streak/category-streak badge's underlying data no longer
    /// supports it (e.g. a completion that helped reach it was reset), not
    /// a general-purpose delete for arbitrary badges.
    func revoke(dedupeKey: String) async throws

    func fetchPointsLedger() async throws -> PointsLedger
    func savePointsLedger(_ ledger: PointsLedger) async throws
}
