import Foundation

/// A single habit's logged state for one calendar day. For a Bad habit,
/// `isComplete` means "successfully avoided that day" — there's no separate
/// relapse/streak-break modeling yet (that's APP_REDESIGN_SPEC.md §8's
/// points/streak system, not built in this pass).
///
/// Three interaction models share this one struct (see `HomeView`'s tap/
/// long-press gesture map): a simple habit only ever uses `isComplete`; a
/// quantity habit (`goal > 1`) uses `count` toward that goal, auto-setting
/// `isComplete` once `count >= goal`; a time-based habit (`timeMode` set)
/// uses `startedAt` instead of toggling completion at all.
struct Completion: Identifiable, Codable, Equatable {
    let id: UUID
    let habitID: Habit.ID
    /// Normalized to the start of its calendar day.
    let date: Date
    var count: Double
    var isComplete: Bool
    /// Time-based habits: when the habit was last "started" today.
    var startedAt: Date?
    /// Real timestamp of the last update — distinct from `date` (which is
    /// day-granularity) — used for Progress's Recent Activity list.
    var loggedAt: Date

    init(
        id: UUID = UUID(),
        habitID: Habit.ID,
        date: Date,
        count: Double = 0,
        isComplete: Bool = false,
        startedAt: Date? = nil,
        loggedAt: Date = .now
    ) {
        self.id = id
        self.habitID = habitID
        self.date = Calendar.current.startOfDay(for: date)
        self.count = count
        self.isComplete = isComplete
        self.startedAt = startedAt
        self.loggedAt = loggedAt
    }
}
