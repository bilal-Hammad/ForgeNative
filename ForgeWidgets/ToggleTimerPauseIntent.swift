import ActivityKit
import AppIntents
import Foundation

/// The Live Activity's pause/resume button (Lock Screen / Dynamic Island).
/// A single toggling `LiveActivityIntent` (iOS 17+) — running → paused →
/// running — so its `perform()` runs entirely in the `ForgeWidgets`
/// extension process without launching the main app, matching the same
/// proven pattern the former `StopTimerIntent` used.
///
/// Two halves, like the old stop intent:
/// 1. **Updates the `Activity`'s `ContentState` right here, right now** so
///    the timer visibly freezes/continues and the button icon flips the
///    instant it's tapped — no round trip to the app. All the pause math is
///    done from the current `ContentState` plus `goalDuration` (a fixed
///    attribute), so the extension never needs the SwiftData store.
/// 2. **Signals the new accumulated-elapsed state** via
///    `SharedTimerPauseSignal` so the persisted `Completion` catches up next
///    foreground (`HomeView.processPendingTimerSignals()`).
struct ToggleTimerPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause or Resume Timer" }

    @Parameter(title: "Habit ID")
    var habitIDString: String

    init() {
        habitIDString = ""
    }

    init(habitID: UUID) {
        habitIDString = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let habitID = UUID(uuidString: habitIDString),
              let activity = Activity<HabitTimerAttributes>.activities.first(where: { $0.attributes.habitID == habitID })
        else {
            return .result()
        }

        let now = Date.now
        let goalDuration = activity.attributes.goalDuration
        let state = activity.content.state

        let newState: HabitTimerAttributes.ContentState
        let signalRunStartedAt: Date?
        // Banked elapsed is the same value in both branches (it's the total
        // elapsed at the moment of the tap); only whether a run segment is
        // live differs.
        let bankedElapsed: TimeInterval

        if state.isPaused {
            // Resume: rebuild the timeline so it ends `pausedRemaining` from
            // now, and re-anchor `effectiveStartDate` so the ticking math
            // still accounts for the banked time.
            let remaining = max(0, state.pausedRemaining)
            let newEnd = now.addingTimeInterval(remaining)
            let newEffectiveStart = newEnd.addingTimeInterval(-goalDuration)
            newState = HabitTimerAttributes.ContentState(
                isPaused: false,
                effectiveStartDate: newEffectiveStart,
                endDate: newEnd,
                pausedRemaining: remaining
            )
            bankedElapsed = max(0, goalDuration - remaining)
            signalRunStartedAt = now
        } else {
            // Pause: freeze the remaining value; stop the ticking view.
            let remaining = max(0, state.endDate.timeIntervalSince(now))
            newState = HabitTimerAttributes.ContentState(
                isPaused: true,
                effectiveStartDate: state.effectiveStartDate,
                endDate: state.endDate,
                pausedRemaining: remaining
            )
            bankedElapsed = max(0, goalDuration - remaining)
            signalRunStartedAt = nil
        }

        await activity.update(ActivityContent(state: newState, staleDate: newState.isPaused ? nil : newState.endDate))
        SharedTimerPauseSignal.record(habitID: habitID, accumulatedElapsed: bankedElapsed, runStartedAt: signalRunStartedAt)
        return .result()
    }
}
