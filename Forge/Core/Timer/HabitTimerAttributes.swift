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
    /// While **running** (`isPaused == false`): the view renders a ticking
    /// `Text(timerInterval: effectiveStartDate...endDate, countsDown: true)`.
    /// `effectiveStartDate` is shifted earlier than the real run-start by
    /// the banked `accumulatedElapsed`, so the system's own ticking math
    /// lines up with total elapsed. While **paused** (`isPaused == true`):
    /// the view must render a *static* value (`pausedRemaining`) instead —
    /// a `timerInterval` view keeps ticking regardless of app pause state,
    /// since the system, not this extension, drives it.
    struct ContentState: Codable, Hashable, Sendable {
        var isPaused: Bool
        /// Real run-start minus banked elapsed — the anchor the ticking
        /// countdown counts from. Recomputed on every resume.
        var effectiveStartDate: Date
        /// `effectiveStartDate + goalDuration` — when the countdown hits 0.
        var endDate: Date
        /// Frozen seconds remaining, rendered statically while paused.
        var pausedRemaining: TimeInterval
    }

    let habitID: UUID
    let habitTitle: String
    let iconSystemName: String
    let color: HabitColor
    /// The habit's goal expressed in seconds — fixed for the life of the
    /// timer. Lets `ToggleTimerPauseIntent` reconstruct the timeline on
    /// resume (`endDate = now + pausedRemaining`, `effectiveStartDate =
    /// endDate - goalDuration`) entirely inside the extension process.
    let goalDuration: TimeInterval
}
