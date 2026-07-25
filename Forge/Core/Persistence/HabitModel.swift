import Foundation
import SwiftData

/// SwiftData persistence entity for `Habit`. Kept deliberately separate from
/// the `Habit` domain struct the rest of the app actually works with — the
/// repository layer is the only thing that ever sees this type, mapping to
/// and from `Habit` — so nothing above the repository boundary needs to know
/// or care that SwiftData is the storage mechanism (same reasoning as the
/// original `HabitRepository` design in APP_REDESIGN_SPEC.md §7).
///
/// `categoryRaw` is stored as a plain `String` rather than the `HabitCategory`
/// enum directly, specifically so `fetch(category:)` can use it in a
/// `#Predicate` reliably — enum-in-predicate support has real historical
/// rough edges across SwiftData versions, and category filtering is an
/// actual, frequent query path (every category-detail screen load), so this
/// isn't a hypothetical concern. `colorRaw`/`unitRaw` are never predicated on
/// anywhere in the app, so they're stored the same way for consistency and
/// forward-compatibility (adding a filter on them later doesn't require a
/// migration), but that's a lower-stakes choice than category's.
///
/// `repeatModeData`/`timeModeData` hold `RepeatMode`/`TimeMode` — enums with
/// associated values — encoded as `Data` via `Codable`. Neither is ever
/// queried/filtered on, only read back out for a specific already-fetched
/// habit, so there's no query-performance cost to this; it sidesteps
/// SwiftData's inconsistent handling of associated-value enums entirely
/// rather than gambling on it working across versions.
@Model
final class HabitModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var categoryRaw: String
    var isHealthKitTracked: Bool
    var sourceTemplateID: String?
    var iconSystemName: String
    var colorRaw: String
    var goal: Double
    var unitRaw: String
    var step: Double
    var repeatModeData: Data
    var timeModeData: Data
    var startDate: Date
    var endDate: Date?
    var notificationsEnabled: Bool
    var remindersAppSyncEnabled: Bool
    var calendarSyncEnabled: Bool
    /// Predicated on directly by Home's active-list query — kept a plain
    /// `Bool`, not derived, for the same query-reliability reason as above.
    var isArchived: Bool
    /// A default value at the property declaration (not just in `init`) is
    /// what lets SwiftData's automatic lightweight migration add this column
    /// to existing installs without a manual migration plan — added after
    /// `HabitModel` already shipped, unlike every field above it.
    var weeklyReflectionEnabled: Bool = true

    /// Cascade delete: removing a habit removes all its completion history
    /// with it — no orphaned rows left behind pointing at a deleted habit.
    @Relationship(deleteRule: .cascade, inverse: \CompletionModel.habit)
    var completions: [CompletionModel] = []

    init(
        id: UUID,
        title: String,
        categoryRaw: String,
        isHealthKitTracked: Bool,
        sourceTemplateID: String?,
        iconSystemName: String,
        colorRaw: String,
        goal: Double,
        unitRaw: String,
        step: Double,
        repeatModeData: Data,
        timeModeData: Data,
        startDate: Date,
        endDate: Date?,
        notificationsEnabled: Bool,
        remindersAppSyncEnabled: Bool,
        calendarSyncEnabled: Bool,
        isArchived: Bool,
        weeklyReflectionEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.categoryRaw = categoryRaw
        self.isHealthKitTracked = isHealthKitTracked
        self.sourceTemplateID = sourceTemplateID
        self.iconSystemName = iconSystemName
        self.colorRaw = colorRaw
        self.goal = goal
        self.unitRaw = unitRaw
        self.step = step
        self.repeatModeData = repeatModeData
        self.timeModeData = timeModeData
        self.startDate = startDate
        self.endDate = endDate
        self.notificationsEnabled = notificationsEnabled
        self.remindersAppSyncEnabled = remindersAppSyncEnabled
        self.calendarSyncEnabled = calendarSyncEnabled
        self.isArchived = isArchived
        self.weeklyReflectionEnabled = weeklyReflectionEnabled
    }
}

extension HabitModel {
    convenience init(habit: Habit) {
        self.init(
            id: habit.id,
            title: habit.title,
            categoryRaw: habit.category.rawValue,
            isHealthKitTracked: habit.isHealthKitTracked,
            sourceTemplateID: habit.sourceTemplateID,
            iconSystemName: habit.iconSystemName,
            colorRaw: habit.color.rawValue,
            goal: habit.goal,
            unitRaw: habit.unit.rawValue,
            step: habit.step,
            repeatModeData: (try? JSONEncoder().encode(habit.repeatMode)) ?? Data(),
            timeModeData: (try? JSONEncoder().encode(habit.timeMode)) ?? Data(),
            startDate: habit.startDate,
            endDate: habit.endDate,
            notificationsEnabled: habit.notificationsEnabled,
            remindersAppSyncEnabled: habit.remindersAppSyncEnabled,
            calendarSyncEnabled: habit.calendarSyncEnabled,
            isArchived: habit.isArchived,
            weeklyReflectionEnabled: habit.weeklyReflectionEnabled
        )
    }

    func update(from habit: Habit) {
        title = habit.title
        categoryRaw = habit.category.rawValue
        isHealthKitTracked = habit.isHealthKitTracked
        iconSystemName = habit.iconSystemName
        colorRaw = habit.color.rawValue
        goal = habit.goal
        unitRaw = habit.unit.rawValue
        step = habit.step
        repeatModeData = (try? JSONEncoder().encode(habit.repeatMode)) ?? repeatModeData
        timeModeData = (try? JSONEncoder().encode(habit.timeMode)) ?? timeModeData
        startDate = habit.startDate
        endDate = habit.endDate
        notificationsEnabled = habit.notificationsEnabled
        remindersAppSyncEnabled = habit.remindersAppSyncEnabled
        calendarSyncEnabled = habit.calendarSyncEnabled
        isArchived = habit.isArchived
        weeklyReflectionEnabled = habit.weeklyReflectionEnabled
    }

    func toHabit() -> Habit {
        let repeatMode = (try? JSONDecoder().decode(RepeatMode.self, from: repeatModeData)) ?? .daily
        let timeMode = (try? JSONDecoder().decode(TimeMode.self, from: timeModeData)) ?? .none
        return Habit(
            id: id,
            title: title,
            category: HabitCategory(rawValue: categoryRaw) ?? .good,
            isHealthKitTracked: isHealthKitTracked,
            sourceTemplateID: sourceTemplateID,
            iconSystemName: iconSystemName,
            color: HabitColor(rawValue: colorRaw) ?? .blue,
            goal: goal,
            unit: HabitUnit(rawValue: unitRaw) ?? .count,
            step: step,
            repeatMode: repeatMode,
            timeMode: timeMode,
            startDate: startDate,
            endDate: endDate,
            notificationsEnabled: notificationsEnabled,
            remindersAppSyncEnabled: remindersAppSyncEnabled,
            calendarSyncEnabled: calendarSyncEnabled,
            weeklyReflectionEnabled: weeklyReflectionEnabled,
            isArchived: isArchived
        )
    }
}
