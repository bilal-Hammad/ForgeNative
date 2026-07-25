import SwiftUI

/// A single earned badge. Display text and color are resolved and stored at
/// award-time (not re-derived from the source habit/category on every
/// render) so a badge still reads correctly even if the habit it was earned
/// on is later renamed, archived, or deleted — same principle as a real
/// achievement record outliving the thing that earned it.
struct Milestone: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: MilestoneKind
    /// `habit.id.uuidString` for `.habitStreak`; `category.rawValue` for
    /// `.categoryStreak`/`.categoryChallenge`; empty for `.points`.
    var scopeID: String
    /// The streak length or points threshold this badge represents.
    var value: Int
    /// `"yyyy-MM"` for `.categoryChallenge`; empty otherwise. Doubles as the
    /// dedupe key's period component so the same month's challenge can't be
    /// awarded twice.
    var periodKey: String
    var title: String
    var subtitle: String
    var earnedDate: Date
    /// Reuses an existing enum's own color rather than inventing a new
    /// serialization: a `HabitCategory.rawValue` (category-scoped badges), a
    /// `HabitColor.rawValue` (matches the earning habit's own card color),
    /// or `"points"` (fixed gold, no natural source color).
    var colorToken: String

    var color: Color {
        if let category = HabitCategory(rawValue: colorToken) {
            return category.accentColor
        }
        if let habitColor = HabitColor(rawValue: colorToken) {
            return habitColor.color
        }
        return Color(red: 0.83, green: 0.68, blue: 0.21)
    }

    /// Stable identity for "has this exact badge already been awarded?"
    /// checks — a badge is uniquely identified by kind + scope + value +
    /// period, not by `id` (which is fresh every time one is created).
    var dedupeKey: String {
        Milestone.dedupeKey(kind: kind, scopeID: scopeID, value: value, periodKey: periodKey)
    }

    static func dedupeKey(kind: MilestoneKind, scopeID: String, value: Int, periodKey: String) -> String {
        "\(kind.rawValue)|\(scopeID)|\(value)|\(periodKey)"
    }

    init(
        id: UUID = UUID(),
        kind: MilestoneKind,
        scopeID: String,
        value: Int,
        periodKey: String = "",
        title: String,
        subtitle: String,
        earnedDate: Date,
        colorToken: String
    ) {
        self.id = id
        self.kind = kind
        self.scopeID = scopeID
        self.value = value
        self.periodKey = periodKey
        self.title = title
        self.subtitle = subtitle
        self.earnedDate = earnedDate
        self.colorToken = colorToken
    }
}
