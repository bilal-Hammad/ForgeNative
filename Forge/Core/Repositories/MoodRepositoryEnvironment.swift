import SwiftUI

private struct MoodRepositoryKey: EnvironmentKey {
    static let defaultValue: MoodRepository = InMemoryMoodRepository()
}

extension EnvironmentValues {
    var moodRepository: MoodRepository {
        get { self[MoodRepositoryKey.self] }
        set { self[MoodRepositoryKey.self] = newValue }
    }
}
