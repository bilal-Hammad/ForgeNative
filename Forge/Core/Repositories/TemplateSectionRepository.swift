import Foundation

/// Manages per-category section customization (APP_REDESIGN_SPEC.md §5's
/// Edit flow) — separate from `HabitRepository`, mirroring the RN app's own
/// separate `useTemplateSectionStore` (SWIFT_REWRITE_INVENTORY.md).
protocol TemplateSectionRepository: Sendable {
    func fetchConfiguration(for category: HabitCategory) async throws -> TemplateSectionConfiguration
    func setActiveSectionOrder(_ order: [String], for category: HabitCategory) async throws
    func softDelete(sectionID: String, for category: HabitCategory) async throws
    func restore(sectionID: String, for category: HabitCategory) async throws
    /// Adds a built-in `TemplateCatalog` section to the active list — no
    /// tier/payment check here per the §10 timing decision: all suggested
    /// sections, including premium-tagged ones, are freely addable until the
    /// real StoreKit 2 entitlement gate lands in Phase 4+.
    func addSuggestedSection(sectionID: String, for category: HabitCategory) async throws
    func addCustomSection(_ section: TemplateSection) async throws
    func updateCustomSection(_ section: TemplateSection) async throws
    /// Reverts order/hidden-state back to default — only affects built-in
    /// sections; user-created custom sections are never deleted by this.
    func resetToDefault(for category: HabitCategory) async throws
}
