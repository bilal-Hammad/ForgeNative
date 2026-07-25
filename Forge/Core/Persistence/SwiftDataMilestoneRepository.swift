import Foundation
import SwiftData

/// The app's real, persistent `MilestoneRepository` implementation.
@ModelActor
actor SwiftDataMilestoneRepository: MilestoneRepository {
    func fetchAll() async throws -> [Milestone] {
        let descriptor = FetchDescriptor<MilestoneModel>(sortBy: [SortDescriptor(\.earnedDate, order: .reverse)])
        return try modelContext.fetch(descriptor).map { $0.toMilestone() }
    }

    func fetchRecent(limit: Int) async throws -> [Milestone] {
        var descriptor = FetchDescriptor<MilestoneModel>(sortBy: [SortDescriptor(\.earnedDate, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { $0.toMilestone() }
    }

    @discardableResult
    func award(_ milestone: Milestone) async throws -> Bool {
        let key = milestone.dedupeKey
        let descriptor = FetchDescriptor<MilestoneModel>(predicate: #Predicate { $0.dedupeKey == key })
        guard try modelContext.fetch(descriptor).isEmpty else { return false }
        modelContext.insert(MilestoneModel(milestone: milestone))
        try modelContext.save()
        return true
    }

    func fetchPointsLedger() async throws -> PointsLedger {
        try fetchOrCreateLedgerModel().toLedger()
    }

    func savePointsLedger(_ ledger: PointsLedger) async throws {
        let model = try fetchOrCreateLedgerModel()
        model.update(from: ledger)
        try modelContext.save()
    }

    private func fetchOrCreateLedgerModel() throws -> PointsLedgerModel {
        let descriptor = FetchDescriptor<PointsLedgerModel>(predicate: #Predicate { $0.singletonKey == "ledger" })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let fresh = PointsLedgerModel(cumulativePoints: 0, lastEvaluatedDay: nil)
        modelContext.insert(fresh)
        try modelContext.save()
        return fresh
    }
}
