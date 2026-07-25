import Foundation

/// Phase 1-style in-memory stub — same rationale as `InMemoryHabitRepository`.
actor InMemoryTemplateSectionRepository: TemplateSectionRepository {
    private var configurations: [HabitCategory: TemplateSectionConfiguration] = [:]

    private func configuration(for category: HabitCategory) -> TemplateSectionConfiguration {
        if let existing = configurations[category] {
            return existing
        }
        let fresh = TemplateSectionConfiguration(activeSectionIDs: TemplateCatalog.defaultSectionIDs(for: category))
        configurations[category] = fresh
        return fresh
    }

    func fetchConfiguration(for category: HabitCategory) async throws -> TemplateSectionConfiguration {
        configuration(for: category)
    }

    func setActiveSectionOrder(_ order: [String], for category: HabitCategory) async throws {
        var config = configuration(for: category)
        config.activeSectionIDs = order
        configurations[category] = config
    }

    func softDelete(sectionID: String, for category: HabitCategory) async throws {
        var config = configuration(for: category)
        config.activeSectionIDs.removeAll { $0 == sectionID }
        if !config.deletedSectionIDs.contains(sectionID) {
            config.deletedSectionIDs.append(sectionID)
        }
        configurations[category] = config
    }

    func restore(sectionID: String, for category: HabitCategory) async throws {
        var config = configuration(for: category)
        config.deletedSectionIDs.removeAll { $0 == sectionID }
        if !config.activeSectionIDs.contains(sectionID) {
            config.activeSectionIDs.append(sectionID)
        }
        configurations[category] = config
    }

    func addSuggestedSection(sectionID: String, for category: HabitCategory) async throws {
        var config = configuration(for: category)
        config.deletedSectionIDs.removeAll { $0 == sectionID }
        if !config.activeSectionIDs.contains(sectionID) {
            config.activeSectionIDs.append(sectionID)
        }
        configurations[category] = config
    }

    func addCustomSection(_ section: TemplateSection) async throws {
        var config = configuration(for: section.category)
        config.customSections.append(section)
        if !config.activeSectionIDs.contains(section.id) {
            config.activeSectionIDs.append(section.id)
        }
        configurations[section.category] = config
    }

    func updateCustomSection(_ section: TemplateSection) async throws {
        var config = configuration(for: section.category)
        if let index = config.customSections.firstIndex(where: { $0.id == section.id }) {
            config.customSections[index] = section
        }
        configurations[section.category] = config
    }

    func resetToDefault(for category: HabitCategory) async throws {
        var config = configuration(for: category)
        let customIDsStillActive = config.activeSectionIDs.filter { id in
            config.customSections.contains { $0.id == id }
        }
        config.activeSectionIDs = TemplateCatalog.defaultSectionIDs(for: category) + customIDsStillActive
        config.deletedSectionIDs.removeAll { id in
            TemplateCatalog.sections(for: category).contains { $0.id == id && $0.tier == .free }
        }
        configurations[category] = config
    }
}
