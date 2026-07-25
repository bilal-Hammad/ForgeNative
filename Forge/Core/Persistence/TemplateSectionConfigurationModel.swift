import Foundation
import SwiftData

/// SwiftData persistence entities for `TemplateSectionConfiguration` — one
/// `TemplateSectionConfigurationModel` per category (Good/Bad/To-Do), each
/// owning zero or more `CustomSectionModel`s via a real cascade-delete
/// relationship (deleting a category's configuration, which never actually
/// happens in practice, would correctly clean up its custom sections too —
/// modeled properly rather than left to dangle).
///
/// `CustomSectionModel.templatesData` encodes a custom section's bundled
/// `[HabitTemplate]` as `Data` rather than a further relationship layer —
/// this is small, rarely-changing blueprint metadata a user edits directly
/// through `EditSectionDetailView`, not high-volume tracked data like
/// completions, so it doesn't carry the same query-performance stakes that
/// justified `CompletionModel`'s indexing.
@Model
final class TemplateSectionConfigurationModel {
    @Attribute(.unique) var categoryRaw: String
    var activeSectionIDs: [String]
    var deletedSectionIDs: [String]

    @Relationship(deleteRule: .cascade, inverse: \CustomSectionModel.configuration)
    var customSections: [CustomSectionModel] = []

    init(categoryRaw: String, activeSectionIDs: [String], deletedSectionIDs: [String]) {
        self.categoryRaw = categoryRaw
        self.activeSectionIDs = activeSectionIDs
        self.deletedSectionIDs = deletedSectionIDs
    }
}

@Model
final class CustomSectionModel {
    @Attribute(.unique) var id: String
    var categoryRaw: String
    var displayName: String
    var tierRaw: String
    var templatesData: Data

    var configuration: TemplateSectionConfigurationModel?

    init(id: String, categoryRaw: String, displayName: String, tierRaw: String, templatesData: Data) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.displayName = displayName
        self.tierRaw = tierRaw
        self.templatesData = templatesData
    }
}

extension CustomSectionModel {
    convenience init(section: TemplateSection) {
        self.init(
            id: section.id,
            categoryRaw: section.category.rawValue,
            displayName: section.displayName,
            tierRaw: section.tier.rawValue,
            templatesData: (try? JSONEncoder().encode(section.templates)) ?? Data()
        )
    }

    func update(from section: TemplateSection) {
        displayName = section.displayName
        tierRaw = section.tier.rawValue
        templatesData = (try? JSONEncoder().encode(section.templates)) ?? templatesData
    }

    func toTemplateSection() -> TemplateSection {
        let templates = (try? JSONDecoder().decode([HabitTemplate].self, from: templatesData)) ?? []
        return TemplateSection(
            id: id,
            category: HabitCategory(rawValue: categoryRaw) ?? .good,
            displayName: displayName,
            tier: SuggestedSectionTier(rawValue: tierRaw) ?? .free,
            templates: templates
        )
    }
}
