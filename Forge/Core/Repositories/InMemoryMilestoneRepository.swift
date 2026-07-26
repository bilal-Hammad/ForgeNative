import Foundation

/// In-memory stub, kept for SwiftUI `#Preview`s only — see
/// `InMemoryHabitRepository`'s doc comment for why this pattern exists
/// alongside the real SwiftData-backed implementation.
actor InMemoryMilestoneRepository: MilestoneRepository {
    private var milestones: [Milestone] = []
    private var ledger = PointsLedger.empty

    func fetchAll() async throws -> [Milestone] {
        milestones
    }

    func fetchRecent(limit: Int) async throws -> [Milestone] {
        Array(milestones.sorted { $0.earnedDate > $1.earnedDate }.prefix(limit))
    }

    @discardableResult
    func award(_ milestone: Milestone) async throws -> Bool {
        guard !milestones.contains(where: { $0.dedupeKey == milestone.dedupeKey }) else { return false }
        milestones.append(milestone)
        return true
    }

    func revoke(dedupeKey: String) async throws {
        milestones.removeAll { $0.dedupeKey == dedupeKey }
    }

    func fetchPointsLedger() async throws -> PointsLedger {
        ledger
    }

    func savePointsLedger(_ ledger: PointsLedger) async throws {
        self.ledger = ledger
    }
}
