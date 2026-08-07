import SwiftUI

/// The three top-level habit categories (APP_REDESIGN_SPEC.md §4 — "Health"
/// was removed as a standalone category; HealthKit-tracked habits now live
/// inside whichever of these three fits them contextually).
enum HabitCategory: String, Codable, CaseIterable, Identifiable {
    case good
    case bad
    case todo

    var id: String { rawValue }

    /// User-facing labels only. Deliberately decoupled from the raw values
    /// below (`good`/`bad`/`todo`), which are persisted in SwiftData and used
    /// to build stable identifiers elsewhere (e.g. `TemplateCatalog`'s
    /// `good-islamic*` section IDs and their StoreKit product IDs) — renaming
    /// those would need a real data migration, so the display rename
    /// (2026-08-07: Good/Bad/To-Do → Build/Destroy/Tasks) changes these
    /// strings and nothing else.
    var displayName: String {
        switch self {
        case .good: "Build"
        case .bad: "Destroy"
        case .todo: "Tasks"
        }
    }

    /// Same mapping as the Home rings strip (`RingsView`) — reused here so
    /// category-scoped Milestone badges read as the same category, not an
    /// arbitrarily different color.
    var accentColor: Color {
        switch self {
        case .good: .green
        case .bad: .red
        case .todo: .blue
        }
    }
}
