import SwiftUI

private struct MilestoneEngineKey: EnvironmentKey {
    static let defaultValue = MilestoneEngine(
        habitRepository: InMemoryHabitRepository(),
        milestoneRepository: InMemoryMilestoneRepository()
    )
}

extension EnvironmentValues {
    var milestoneEngine: MilestoneEngine {
        get { self[MilestoneEngineKey.self] }
        set { self[MilestoneEngineKey.self] = newValue }
    }
}
