import SwiftUI

/// SwiftUI environment plumbing so any view can reach the shared
/// `HabitRepository` (`@Environment(\.habitRepository)`) without threading
/// it through every initializer by hand.
private struct HabitRepositoryKey: EnvironmentKey {
    static let defaultValue: HabitRepository = InMemoryHabitRepository()
}

extension EnvironmentValues {
    var habitRepository: HabitRepository {
        get { self[HabitRepositoryKey.self] }
        set { self[HabitRepositoryKey.self] = newValue }
    }
}
