import SwiftUI

private struct MilestoneRepositoryKey: EnvironmentKey {
    static let defaultValue: MilestoneRepository = InMemoryMilestoneRepository()
}

extension EnvironmentValues {
    var milestoneRepository: MilestoneRepository {
        get { self[MilestoneRepositoryKey.self] }
        set { self[MilestoneRepositoryKey.self] = newValue }
    }
}
