import SwiftUI

private struct TemplateSectionRepositoryKey: EnvironmentKey {
    static let defaultValue: TemplateSectionRepository = InMemoryTemplateSectionRepository()
}

extension EnvironmentValues {
    var templateSectionRepository: TemplateSectionRepository {
        get { self[TemplateSectionRepositoryKey.self] }
        set { self[TemplateSectionRepositoryKey.self] = newValue }
    }
}
