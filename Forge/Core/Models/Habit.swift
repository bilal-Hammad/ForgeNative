import Foundation

/// Core habit model. Fields grow as each screen's real feature work lands
/// per APP_REDESIGN_SPEC.md — streak/point state still isn't here yet
/// (Progress-screen phase).
///
/// §12 editability rule (enforced in `HabitFormView`, not this model):
/// title/icon/color are editable on every habit, including HealthKit-tracked
/// ones; `goal`/`unit`/`step` are locked once `isHealthKitTracked` is true,
/// since those are fixed by whatever HK quantity type the habit maps to.
///
/// `goal`/`unit`/`step` are no longer optional as of the per-habit smart
/// defaults pass — every habit has a real value (a plain daily habit is
/// `goal: 1, unit: .count, step: 1`, matching "Make your Bed" as the
/// reference example), not a blank/nil field a user has to fill in.
struct Habit: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var category: HabitCategory
    /// §4/§7: habits that auto-track via HealthKit get a small Apple Health
    /// badge on their card, and real read/write/background-delivery sync
    /// via `HealthKitService` — see that type and `HealthKitTypeMapping`.
    var isHealthKitTracked: Bool
    /// The `HabitTemplate.id` this habit was created from, if any (nil for
    /// a manually-created custom habit). Set once at creation and never
    /// changed afterward — title/icon *are* user-editable even for
    /// HealthKit-tracked habits (§12), so neither can be used to look up
    /// which real HealthKit type this habit maps to; this stable id is
    /// `HealthKitTypeMapping`'s lookup key instead.
    var sourceTemplateID: String?
    var iconSystemName: String
    var color: HabitColor

    var goal: Double
    var unit: HabitUnit
    /// UI label: "Increment" — how much each tap adds toward `goal`.
    var step: Double

    var repeatMode: RepeatMode
    /// §12: "Time" (plain fixed-time picker) plus the Forge-specific
    /// "Every X Hours" / "X Times a Day" interval sub-modes.
    var timeMode: TimeMode
    var startDate: Date
    var endDate: Date?

    /// Managed centrally from Settings now, not the create/edit form —
    /// `SettingsView`'s Notifications section drills into
    /// `HabitSyncSettingsDetailView` per habit, which is the only place
    /// these three change after creation. `notificationsEnabled` gates
    /// whether `HabitNotificationScheduler` schedules reminders for this
    /// habit's `timeMode`, alongside the global Settings master toggle.
    /// EventKit sync (Reminders app / Calendar, below) remains a state-only
    /// stub — no real EventKit calls exist yet, same as before this moved.
    var notificationsEnabled: Bool
    var remindersAppSyncEnabled: Bool
    var calendarSyncEnabled: Bool

    /// §13: per-habit mute for the weekly reflection notification (the
    /// global toggle lives in `SettingsView`/`WeeklyReflectionScheduler`) —
    /// "togglable per-habit too (mute reflection notifications for specific
    /// habits without disabling all of them)". Same shape as
    /// `notificationsEnabled` above, independent of it — a habit can have
    /// its per-tap reminders on and weekly reflection off, or vice versa.
    var weeklyReflectionEnabled: Bool

    /// Archived habits are hidden from Home's active list but not deleted —
    /// surfaced in Profile's Archived Habits screen with an unarchive action.
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String,
        category: HabitCategory,
        isHealthKitTracked: Bool = false,
        sourceTemplateID: String? = nil,
        iconSystemName: String = "checkmark.circle",
        color: HabitColor = .blue,
        goal: Double = 1,
        unit: HabitUnit = .count,
        step: Double = 1,
        repeatMode: RepeatMode = .daily,
        timeMode: TimeMode = .none,
        startDate: Date = .now,
        endDate: Date? = nil,
        notificationsEnabled: Bool = true,
        remindersAppSyncEnabled: Bool = false,
        calendarSyncEnabled: Bool = false,
        weeklyReflectionEnabled: Bool = true,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.isHealthKitTracked = isHealthKitTracked
        self.sourceTemplateID = sourceTemplateID
        self.iconSystemName = iconSystemName
        self.color = color
        self.goal = goal
        self.unit = unit
        self.step = step
        self.repeatMode = repeatMode
        self.timeMode = timeMode
        self.startDate = startDate
        self.endDate = endDate
        self.notificationsEnabled = notificationsEnabled
        self.remindersAppSyncEnabled = remindersAppSyncEnabled
        self.calendarSyncEnabled = calendarSyncEnabled
        self.weeklyReflectionEnabled = weeklyReflectionEnabled
        self.isArchived = isArchived
    }
}
