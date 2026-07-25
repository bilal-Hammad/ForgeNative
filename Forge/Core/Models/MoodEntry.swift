import Foundation

/// One day's optional mood check-in (APP_REDESIGN_SPEC.md §13) — same
/// one-record-per-day shape as `Completion`, but deliberately its own model
/// rather than bolted onto `Completion`/`Habit`: mood isn't scoped to a
/// habit, doesn't participate in `PointsLedger`/streak math at all, and is
/// purely observational/reflective data, not something to "perform well"
/// at (§13's own explicit recommendation).
///
/// `date` is the calendar day being reflected on (normalized to local
/// midnight, like every other day-keyed record in this app);
/// `loggedAt` is the real timestamp the entry was made or last changed —
/// same split `Completion` already uses, kept for the same reason
/// (`loggedAt` is what a future "recent activity"-style mood view would
/// sort by, distinct from which day it's *for*).
struct MoodEntry: Identifiable, Codable, Equatable {
    let id: UUID
    /// Normalized to the start of its calendar day — one entry per day.
    let date: Date
    var mood: MoodLevel
    var loggedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        mood: MoodLevel,
        loggedAt: Date = .now
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.mood = mood
        self.loggedAt = loggedAt
    }
}
