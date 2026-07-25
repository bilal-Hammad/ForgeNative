import Foundation
import SwiftData

/// The app's real, persistent `TemplateSectionRepository` implementation —
/// replaces `InMemoryTemplateSectionRepository` for actual use (that type
/// now exists only for SwiftUI Previews). One `TemplateSectionConfigurationModel`
/// row per category, created lazily on first access with the default active
/// set, same as the in-memory version's behavior — just durable now.
@ModelActor
actor SwiftDataTemplateSectionRepository: TemplateSectionRepository {
    private func fetchOrCreateConfiguration(for category: HabitCategory) throws -> TemplateSectionConfigurationModel {
        let categoryRaw = category.rawValue
        let descriptor = FetchDescriptor<TemplateSectionConfigurationModel>(
            predicate: #Predicate { $0.categoryRaw == categoryRaw }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let fresh = TemplateSectionConfigurationModel(
            categoryRaw: categoryRaw,
            activeSectionIDs: TemplateCatalog.defaultSectionIDs(for: category),
            deletedSectionIDs: []
        )
        modelContext.insert(fresh)
        try modelContext.save()
        return fresh
    }

    private func toConfiguration(_ model: TemplateSectionConfigurationModel) -> TemplateSectionConfiguration {
        TemplateSectionConfiguration(
            activeSectionIDs: model.activeSectionIDs,
            deletedSectionIDs: model.deletedSectionIDs,
            customSections: model.customSections.map { $0.toTemplateSection() }
        )
    }

    func fetchConfiguration(for category: HabitCategory) async throws -> TemplateSectionConfiguration {
        toConfiguration(try fetchOrCreateConfiguration(for: category))
    }

    func setActiveSectionOrder(_ order: [String], for category: HabitCategory) async throws {
        let model = try fetchOrCreateConfiguration(for: category)
        model.activeSectionIDs = order
        try modelContext.save()
    }

    func softDelete(sectionID: String, for category: HabitCategory) async throws {
        let model = try fetchOrCreateConfiguration(for: category)
        model.activeSectionIDs.removeAll { $0 == sectionID }
        if !model.deletedSectionIDs.contains(sectionID) {
            model.deletedSectionIDs.append(sectionID)
        }
        try modelContext.save()
    }

    func restore(sectionID: String, for category: HabitCategory) async throws {
        let model = try fetchOrCreateConfiguration(for: category)
        model.deletedSectionIDs.removeAll { $0 == sectionID }
        if !model.activeSectionIDs.contains(sectionID) {
            model.activeSectionIDs.append(sectionID)
        }
        try modelContext.save()
    }

    func addSuggestedSection(sectionID: String, for category: HabitCategory) async throws {
        let model = try fetchOrCreateConfiguration(for: category)
        model.deletedSectionIDs.removeAll { $0 == sectionID }
        if !model.activeSectionIDs.contains(sectionID) {
            model.activeSectionIDs.append(sectionID)
        }
        try modelContext.save()
    }

    func addCustomSection(_ section: TemplateSection) async throws {
        let model = try fetchOrCreateConfiguration(for: section.category)
        let custom = CustomSectionModel(section: section)
        custom.configuration = model
        modelContext.insert(custom)
        if !model.activeSectionIDs.contains(section.id) {
            model.activeSectionIDs.append(section.id)
        }
        try modelContext.save()
    }

    func updateCustomSection(_ section: TemplateSection) async throws {
        let model = try fetchOrCreateConfiguration(for: section.category)
        if let existing = model.customSections.first(where: { $0.id == section.id }) {
            existing.update(from: section)
            try modelContext.save()
        }
    }

    func resetToDefault(for category: HabitCategory) async throws {
        let model = try fetchOrCreateConfiguration(for: category)
        let customIDsStillActive = model.activeSectionIDs.filter { id in
            model.customSections.contains { $0.id == id }
        }
        model.activeSectionIDs = TemplateCatalog.defaultSectionIDs(for: category) + customIDsStillActive
        model.deletedSectionIDs.removeAll { id in
            TemplateCatalog.sections(for: category).contains { $0.id == id && $0.tier == .free }
        }
        try modelContext.save()
    }
}
