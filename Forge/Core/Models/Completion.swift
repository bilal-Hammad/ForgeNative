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
    /// Time-based habits: the current *running* segment's start (this is the
    /// `runStartedAt` of the accumulated-elapsed model). Non-nil while the
    /// timer is actively running; **nil while paused** (or never started).
    /// A paused-but-not-finished timer is `startedAt == nil` with
    /// `accumulatedElapsed > 0` — see `isTimerPaused`. Reversed the earlier
    /// "no pause, only start/cancel" decision to back the Live Activity
    /// pause/resume redesign (2026-07-30) — see CLAUDE.md.
    var startedAt: Date?
    /// Time banked from previous run segments before the current one, in
    /// seconds. The naive `now - startedAt` breaks the moment pause exists
    /// (wall-clock keeps advancing while paused), so total elapsed is
    /// `accumulatedElapsed + (now - startedAt)` while running, or just
    /// `accumulatedElapsed` while paused. Zero for a fresh/never-paused
    /// timer, so the running case degrades to the original `now - startedAt`.
    var accumulatedElapsed: TimeInterval
    /// Real timestamp of the last update — distinct from `date` (which is
    /// day-granularity) — used for Progress's Recent Activity list.
    var loggedAt: Date
    /// Every `HKSample.uuid` Forge itself has written back to Health for
    /// this specific day's completion (one per manual tap/long-press/timer-
    /// completion that produced a write — a quantity habit tapped several
    /// times before reaching goal accumulates one per tap). Empty for a
    /// non-HealthKit habit, or for a HealthKit-tracked habit whose
    /// completion came entirely from real external data (a genuine Steps/
    /// Sleep reading Forge only *read*, never wrote). This is what makes
    /// "Reset" able to delete *exactly* the samples Forge itself created —
    /// never a real, externally-sourced Health record — see
    /// `HomeView.resetHabit`.
    var healthKitSampleUUIDs: [UUID]

    init(
        id: UUID = UUID(),
        habitID: Habit.ID,
        date: Date,
        count: Double = 0,
        isComplete: Bool = false,
        startedAt: Date? = nil,
        accumulatedElapsed: TimeInterval = 0,
        loggedAt: Date = .now,
        healthKitSampleUUIDs: [UUID] = []
    ) {
        self.id = id
        self.habitID = habitID
        self.date = Calendar.current.startOfDay(for: date)
        self.count = count
        self.isComplete = isComplete
        self.startedAt = startedAt
        self.accumulatedElapsed = accumulatedElapsed
        self.loggedAt = loggedAt
        self.healthKitSampleUUIDs = healthKitSampleUUIDs
    }

    // MARK: - Timer state (accumulated-elapsed model)

    /// A timer is "active" (running or paused) if it has a running segment
    /// or any banked time. Meaningless for a completed habit — callers
    /// already gate on `!isComplete` where it matters.
    var isTimerActive: Bool { startedAt != nil || accumulatedElapsed > 0 }

    /// Actively counting up right now.
    var isTimerRunning: Bool { startedAt != nil }

    /// Started, has banked progress, but not currently counting.
    var isTimerPaused: Bool { startedAt == nil && accumulatedElapsed > 0 }

    /// Total elapsed time as of `now`: banked segments plus the live one.
    func elapsed(asOf now: Date = .now) -> TimeInterval {
        accumulatedElapsed + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }
}
