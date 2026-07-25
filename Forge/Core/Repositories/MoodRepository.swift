import Foundation

/// Storage for §13's daily mood check-in. Same role as `HabitRepository`/
/// `MilestoneRepository` — the only interface the mood check-in card (and,
/// later, a Progress correlation card) talks to; concrete storage is
/// swappable behind it.
///
/// **Designed for the future correlation feature now, even though that
/// feature isn't built this pass**: `fetchEntries(from:to:)` returns the
/// same shape of bounded range query `HabitRepository.fetchCompletions
/// (from:to:)` already does, over the same `Date` axis — so a later
/// correlation query can fetch both for one date range and join them
/// client-side by `date`, without either repository needing to change
/// shape. `MoodLevel.scoreValue` is the numeric axis that join would
/// average against a completion rate.
protocol MoodRepository: Sendable {
    /// A single day's entry, if one was logged — backs the Home check-in
    /// card's "already logged today, show it as selected" state.
    func fetchEntry(for date: Date) async throws -> MoodEntry?
    /// Bounded range query — the one a future mood-vs-habit-completion
    /// correlation card would use, joined against
    /// `HabitRepository.fetchCompletions(from:to:)`/
    /// `fetchCategoryCompletionRates(habits:from:to:)` for the same range.
    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [MoodEntry]
    /// Logs or overwrites the entry for `entry.date` — mood check-in is
    /// always changeable (tapping a different option after already logging
    /// today just updates it), never a locked one-shot.
    func upsertEntry(_ entry: MoodEntry) async throws
}
