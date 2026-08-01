import EventKit
import Foundation

/// The only place that talks to `EKEventStore` — real one-way sync
/// (Forge → Calendar/Reminders, never the reverse; Forge's own completion
/// state and habit data are always authoritative) for a habit's "Sync to
/// Calendar"/"Sync to Reminders App" toggles. Views and stores never touch
/// EventKit directly, matching this project's existing repository/service
/// shape (`HabitRepository`, `HealthKitService`) — generalized here to the
/// EventKit boundary, per CLAUDE.md's Engineering Standard #2.
///
/// **Two structurally different sync strategies, not a shared one** —
/// driven by a real EventKit constraint, not stylistic preference:
/// - **Calendar**: one long-lived recurring `EKEvent` per habit
///   (`Habit.calendarEventIdentifier`), using a real `EKRecurrenceRule`
///   mapped from `RepeatMode`. Forge never needs to know *which* future
///   occurrence is "today's" — it only ever creates/updates/removes the
///   one master event — so native recurrence is a clean fit.
/// - **Reminders**: Forge *does* need day-level granularity (completing a
///   habit today must complete only today's `EKReminder`, matched by due
///   date) — but a recurring `EKReminder`'s completion state is a single
///   flag on the one object, not tracked per-occurrence the way a
///   recurring `EKEvent` is. Using `recurrenceRules` here would make
///   "complete just today's" impossible to express correctly. So Reminders
///   sync instead creates fresh, non-recurring `EKReminder`s for *today's*
///   occurrence(s) every time sync runs, tracked in
///   `Habit.reminderIdentifiers` (plural — `.everyXHours`/`.timesADay`
///   produce more than one same-day reminder, each independently
///   completable at its own time).
///
/// **A real, deliberate judgment call this design implies**: since nothing
/// in this app runs a scheduled daily background job, a habit's Reminders
/// sync only ever gets *today's* occurrence(s) actually created at the
/// moment sync runs (habit created/edited/completed, or the app opened —
/// see `HomeView.reload()`, which also calls this as a lightweight daily
/// catch-up). A habit that's neither touched nor opened for several days
/// in a row won't have those in-between days' Reminders created at all.
/// This wasn't in the task's explicit trigger list (create/update/delete/
/// complete) — flagged here rather than silently assumed, since building a
/// real background-scheduling mechanism is real, separate scope (matching
/// `HabitNotificationScheduler`'s own local-notification approach, which
/// has the same "only as fresh as the app being opened" property and
/// documents it the same way).
protocol CalendarSyncService: Sendable {
    /// Synchronous — `EKEventStore.authorizationStatus(for:)` is itself a
    /// synchronous, non-isolated query (matches `HealthKitService
    /// .writeAuthorizationStatus(for:)`'s exact precedent for exposing a
    /// raw system authorization type directly rather than wrapping it).
    nonisolated func calendarAuthorizationStatus() -> EKAuthorizationStatus
    nonisolated func remindersAuthorizationStatus() -> EKAuthorizationStatus

    /// Requests access only if not already determined — safe to call every
    /// time a toggle turns on; a no-op returning the current state once the
    /// user has already answered. iOS 17+ only (`requestFullAccessToEvents`/
    /// `ToReminders`) — this project's deployment target is 26.0, well past
    /// the iOS 17 line where the deprecated completion-handler
    /// `requestAccess(to:)` API would otherwise be needed as a fallback, so
    /// no fallback path exists here (confirmed against `project.yml`'s
    /// `deploymentTarget`, not assumed).
    @discardableResult
    func requestCalendarAccessIfNeeded() async -> Bool
    @discardableResult
    func requestRemindersAccessIfNeeded() async -> Bool

    /// Creates/updates/removes whatever `EKEvent`/`EKReminder`(s) this
    /// habit's current toggle state + schedule call for, and persists the
    /// resulting identifiers back onto the habit via the repository this
    /// service was constructed with — callers don't re-save anything
    /// themselves (matches `HealthKitService`'s own observer-update shape).
    /// Safe to call unconditionally any time a habit is created, edited,
    /// completed, or the app opens; internally a no-op for whichever half
    /// (Calendar/Reminders) isn't enabled, unsupported for this habit's
    /// schedule, or not authorized.
    func sync(habit: Habit) async

    /// Removes this habit's `EKEvent`/`EKReminder`(s) without touching the
    /// habit record — call with the about-to-be-deleted `Habit` right
    /// before `HabitRepository.delete(id:)`, since the identifiers live on
    /// the habit itself and won't be retrievable afterward.
    func removeSync(for habit: Habit) async

    /// Pushes one day's completion state to that day's matching
    /// `EKReminder`(s) (`isCompleted` + `completionDate`) — a single-field
    /// one-way push, never read back. No-ops if Reminders sync isn't active
    /// for this habit. See this type's doc comment for why a multi-
    /// occurrence day (`.everyXHours`/`.timesADay`) mirrors the same
    /// day-level `isComplete` onto *every* one of that day's reminders —
    /// Forge's own `Completion` model has no finer-grained "which specific
    /// occurrence" tracking to mirror more precisely than that.
    func mirrorCompletion(habit: Habit, completion: Completion) async
}

extension Habit {
    /// `nil` when Calendar sync is fully supported for this habit's current
    /// schedule; otherwise the exact reason to show as the toggle's
    /// disabled-state caption. Two real, distinct EventKit limitations
    /// (not shortcuts) force this:
    /// - `.everyXHours`/`.timesADay` `TimeMode`: a single `EKEvent`
    ///   (timed or all-day) can't represent multiple distinct times within
    ///   one day the way Reminders' multi-occurrence-per-day design can.
    /// - `.timesPerWeek` `RepeatMode`: `EKRecurrenceRule` has no "N times a
    ///   week, any days" concept — its weekly recurrence needs fixed
    ///   `daysOfTheWeek`, which this repeat mode deliberately doesn't have
    ///   (Forge itself doesn't enforce which specific days count toward it
    ///   either — see `HabitNotificationScheduler`'s own doc comment on the
    ///   same limitation for local notifications).
    var calendarSyncUnsupportedReason: String? {
        switch timeMode {
        case .everyXHours, .timesADay:
            return "Calendar doesn't support multiple times per day — use Reminders instead."
        case .prayerRelative:
            return "Calendar can't track prayer times that shift daily — use Reminders instead."
        case .none, .fixedTime:
            break
        }
        if case .timesPerWeek = repeatMode {
            return "Calendar doesn't support a flexible \"times per week\" schedule — use Reminders instead."
        }
        return nil
    }

    var isCalendarSyncSupported: Bool { calendarSyncUnsupportedReason == nil }
}
