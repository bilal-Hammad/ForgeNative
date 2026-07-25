import Foundation

/// The single interface every consumer — the phone app, and later a
/// WidgetKit widget, Watch app, or Siri/App Intent — reads and writes habit
/// data through (APP_REDESIGN_SPEC.md §7). Concrete storage (local DB,
/// CloudKit, Supabase, or some combination) is decided in a later phase
/// without this protocol needing to change.
protocol HabitRepository: Sendable {
    func fetchAll() async throws -> [Habit]
    func fetch(category: HabitCategory) async throws -> [Habit]
    func save(_ habit: Habit) async throws
    func delete(id: Habit.ID) async throws

    /// Completions for a single calendar day, across all habits — enough to
    /// compute the §1 rings strip's per-category percentages.
    func fetchCompletions(for date: Date) async throws -> [Completion]
    /// Completions across an inclusive date range, across all habits —
    /// backs Progress's Streak chart and (once built) Habit Trends. Scoped
    /// to a range rather than "fetch everything and filter in Swift" so this
    /// stays fast as completion history grows into years of data per habit.
    func fetchCompletions(from startDate: Date, to endDate: Date) async throws -> [Completion]
    /// Completions for a single habit across a date range — the same
    /// indexed access pattern as the range query above, scoped one
    /// dimension further so a habit detail page's stats (streaks, all-time
    /// rate, quantity totals) don't require pulling every other habit's
    /// rows for the same range. Backed by `CompletionModel`'s existing
    /// `(habitID, date)` composite index.
    func fetchCompletions(habitID: Habit.ID, from startDate: Date, to endDate: Date) async throws -> [Completion]
    /// Upserts a full `Completion` record (keyed by habitID + day) — the
    /// caller (Home's tap/long-press gesture logic) computes count/
    /// isComplete/startedAt per the habit's type; the repository just
    /// persists whatever it's given.
    func upsertCompletion(_ completion: Completion) async throws

    /// Most-recently-logged completions across all habits, newest first —
    /// backs Progress's Recent Activity card.
    func fetchRecentCompletions(limit: Int) async throws -> [Completion]

    /// Per-day, per-category completion rates across a date range — the
    /// weekly strip's exact need (§1), computed inside the repository
    /// rather than by fetching every raw `Completion` row in the range and
    /// aggregating in the caller. Measured cause: returning a large
    /// `[Completion]` array (hundreds of rows, for a multi-week prefetch
    /// radius) across the `@ModelActor` boundary carries overhead that
    /// scales with the returned payload size — confirmed via `os_log`
    /// timing (~450-500ms for ~600 rows vs ~10-25ms for ~20 rows, on top of
    /// an actual SQLite fetch time that stayed fast — 20-50ms — in both
    /// cases), and unaffected by how the calling `Task` is dispatched
    /// (plain `Task`, `Task.detached`, elevated priority all showed the
    /// same overhead). Returning only the small aggregated result (one
    /// entry per day, not one per habit per day) avoids that cost instead
    /// of trying to out-schedule it. See CLAUDE.md's "Home weekly strip
    /// prefetch" entry for the full investigation.
    func fetchCategoryCompletionRates(
        habits: [Habit], from startDate: Date, to endDate: Date
    ) async throws -> [Date: (good: Double, bad: Double, todo: Double)]
}
