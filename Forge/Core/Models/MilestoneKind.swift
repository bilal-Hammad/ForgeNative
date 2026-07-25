import Foundation

/// The three milestone categories from APP_REDESIGN_SPEC.md §11 — the
/// "Category Challenge" grouping is implemented at the top-level
/// `HabitCategory` (Good/Bad/To-Do) granularity, not the finer browse-time
/// `TemplateSection` granularity the spec's wording ("a section") literally
/// names: `Habit` only stores which of the three top-level categories it
/// belongs to, not which section it was originally added from, so
/// per-section tracking isn't available without a larger model change.
/// Good/Bad/To-Do is the same granularity the rest of Progress (rings,
/// breakdown, trends) already uses, and it's the practical unit achievable
/// here without that change.
enum MilestoneKind: String, Codable {
    /// A single habit's streak crossing a threshold (7/30/100/365 days).
    case habitStreak
    /// All active habits in a category strung together for a threshold
    /// number of consecutive days.
    case categoryStreak
    /// Every active habit in a category completed every day of one fully-
    /// elapsed calendar month.
    case categoryChallenge
    /// Cumulative points (§8) crossing a threshold.
    case points
}
