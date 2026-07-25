import SwiftUI

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue = HealthKitService(
        habitRepository: InMemoryHabitRepository(),
        milestoneEngine: MilestoneEngine(
            habitRepository: InMemoryHabitRepository(),
            milestoneRepository: InMemoryMilestoneRepository()
        )
    )
}

extension EnvironmentValues {
    var healthKitService: HealthKitService {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }
}
