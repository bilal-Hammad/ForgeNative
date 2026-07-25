import Foundation

/// A thematic grouping of suggested habits within one category's detail
/// browser (APP_REDESIGN_SPEC.md §5) — e.g. Good/"Health & Fitness",
/// Bad/"Substances". Replaces the old RN app's A–Z alphabetical grouping.
struct TemplateSection: Identifiable, Codable, Equatable {
    let id: String
    var category: HabitCategory
    var displayName: String
    var tier: SuggestedSectionTier
    var templates: [HabitTemplate]
}
