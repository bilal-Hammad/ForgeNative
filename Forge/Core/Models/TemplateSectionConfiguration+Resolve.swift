import Foundation

extension TemplateSectionConfiguration {
    /// Merges `TemplateCatalog`'s built-in sections with this configuration's
    /// custom sections, resolved into the actual visible, ordered list —
    /// what `CategoryDetailView` and `EditSectionsView` both display.
    func resolvedActiveSections(for category: HabitCategory) -> [TemplateSection] {
        let byID = lookupTable(for: category)
        return activeSectionIDs.compactMap { byID[$0] }
    }

    func resolvedDeletedSections(for category: HabitCategory) -> [TemplateSection] {
        let byID = lookupTable(for: category)
        return deletedSectionIDs.compactMap { byID[$0] }
    }

    /// Built-in sections not currently active — the "Add Suggested Section"
    /// pool. No tier/payment filtering here (§10 timing decision).
    func availableSuggestedSections(for category: HabitCategory) -> [TemplateSection] {
        TemplateCatalog.sections(for: category).filter { !activeSectionIDs.contains($0.id) }
    }

    private func lookupTable(for category: HabitCategory) -> [String: TemplateSection] {
        var table = Dictionary(uniqueKeysWithValues: TemplateCatalog.sections(for: category).map { ($0.id, $0) })
        for custom in customSections {
            table[custom.id] = custom
        }
        return table
    }
}
