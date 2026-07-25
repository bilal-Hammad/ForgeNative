import Foundation

/// Per-category, per-user customization of which sections show, in what
/// order, plus soft-deleted ("Recently Deleted") sections and user-created
/// custom sections. `TemplateCatalog`'s built-in sections are just data —
/// this is the actual state that used to be missing entirely (every user
/// saw every built-in section, unordered, with no way to hide/reorder/add).
struct TemplateSectionConfiguration: Codable, Equatable {
    /// Ordered IDs of currently-visible sections (built-in or custom).
    var activeSectionIDs: [String] = []
    /// Soft-deleted section IDs — shown in "Recently Deleted" with a Restore
    /// action, not a permanent delete.
    var deletedSectionIDs: [String] = []
    /// User-created sections (not part of `TemplateCatalog`).
    var customSections: [TemplateSection] = []
}
