import ActivityKit
import Foundation

/// ActivityKit attributes for a running time-unit habit's timer — this
/// exact file is compiled directly into **both** the main `Forge` target
/// (which starts/ends the Activity from `HabitTimerCoordinator`) and the
/// `ForgeWidgets` extension (which renders it in the Dynamic Island/Lock
/// Screen). No shared framework boundary — matches this project's existing
/// preference for direct multi-target file references over a framework for
/// something this small (see `HabitColor`, also referenced from both
/// targets for exactly this reason).
///
/// The timeline lives entirely in `ContentState` (not the fixed attributes)
/// because pause/resume shifts the effective start/end — see the
/// accumulated-elapsed model in `Completion` and the pause/resume redesign
/// (2026-07-30, CLAUDE.md). `goalDuration` is fixed (the habit's goal in
/// seconds) so the widget/intent can recompute the timeline on resume
/// without a round trip to the app.
struct HabitTimerAttributes: ActivityAttributes, Sendable {
    /// The view renders one `Text(timerInterval: effectiveStartDate...endDate,
    /// pauseTime: pausedAt, countsDown: true)` in every state. `pausedAt` is
    /// the mechanism: `nil` while running (the system ticks it down), and the
    /// pause instant while paused (the system *freezes* it there, natively,
    /// staying correct while the extension is suspended). This replaced an
    /// earlier design that swapped between a ticking `Text(timerInterval:)`
    /// and a hand-formatted static `Text` on an `isPaused` flag — real-device
    /// logs (2026-07-30) proved the `Activity.update` to the paused state
    /// *did* arrive, but the system-rendered ticking text never repainted to
    /// the static replacement, so the countdown kept ticking. `pauseTime` is
    /// Apple's purpose-built API for a pausable timer and doesn't rely on a
    /// view-type swap re-rendering. `effectiveStartDate` is the real run-start
    /// shifted earlier by banked `accumulatedElapsed`, recomputed on resume.
    struct ContentState: Codable, Hashable, Sendable {
        var effectiveStartDate: Date
        /// `effectiveStartDate + goalDuration` — when the countdown hits 0.
        var endDate: Date
        /// `nil` while running; the instant the timer was paused otherwise.
        var pausedAt: Date?

        var isPaused: Bool { pausedAt != nil }
    }

    let habitID: UUID
    let habitTitle: String
    let iconSystemName: String
    let color: HabitColor
    /// The habit's goal expressed in seconds — fixed for the life of the
    /// timer. Lets `ToggleTimerPauseIntent` reconstruct the timeline on
    /// resume (`endDate = now + remaining`, where `remaining = endDate -
    /// pausedAt`, then `effectiveStartDate = endDate - goalDuration`) without
    /// touching the app-side store.
    let goalDuration: TimeInterval
}
