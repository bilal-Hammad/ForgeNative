import SwiftUI

/// The three top-level habit categories (APP_REDESIGN_SPEC.md §4 — "Health"
/// was removed as a standalone category; HealthKit-tracked habits now live
/// inside whichever of these three fits them contextually).
enum HabitCategory: String, Codable, CaseIterable, Identifiable {
    case good
    case bad
    case todo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .good: "Good"
        case .bad: "Bad"
        case .todo: "To-Do"
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
