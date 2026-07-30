import ActivityKit
import AppIntents
import Foundation
import os

/// Permanent — this path is genuinely hard to observe (a Lock Screen tap
/// that runs in a background app-process intent, unreachable by XCUITest or
/// Simulator), and a silent failure here is exactly the "pause does nothing"
/// bug this logging was added to root-cause. One line at entry + one on the
/// no-activity path, matching this project's `habitDeletionLogger`/
/// `CalendarSync` precedent. Watch with:
/// log stream --predicate 'category == "PauseIntent"' (or idevicesyslog).
private let pauseIntentLogger = Logger(subsystem: "com.bilalhammad.forge.native", category: "PauseIntent")

/// The Live Activity's pause/resume button (Lock Screen / Dynamic Island).
/// A single toggling `LiveActivityIntent` (iOS 17+) — running → paused →
/// running.
///
/// **Compiled into BOTH the `Forge` app target and the `ForgeWidgets`
/// extension** (this file lives in `Forge/Core/Timer/` and is also listed in
/// `ForgeWidgets`' sources, matching `HabitTimerAttributes`/
/// `SharedTimerPauseSignal`). This is load-bearing, not incidental: Apple's
/// documented requirement is that an App Intent driving a widget/Live
/// Activity button be a member of both targets, because the system routes a
/// `LiveActivityIntent`'s `perform()` to the *app's* process — an
/// extension-only intent silently does nothing when tapped, which was the
/// root cause of the "pause button does nothing" bug (the former
/// `StopTimerIntent`, and the first cut of this intent, were both
/// extension-only). See RESULTS.md (2026-07-30).
///
/// Two halves:
/// 1. **Updates the `Activity`'s `ContentState` immediately** so the timer
///    visibly freezes/continues and the button icon flips. All the pause
///    math comes from the current `ContentState` plus `goalDuration` (a fixed
///    attribute), so it never needs the SwiftData store (unreachable from the
///    extension, and undesirable to touch from a background intent run).
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
        pauseIntentLogger.log("perform() ran in \(ProcessInfo.processInfo.processName, privacy: .public) for habitID=\(habitIDString, privacy: .public)")
        guard let habitID = UUID(uuidString: habitIDString),
              let activity = Activity<HabitTimerAttributes>.activities.first(where: { $0.attributes.habitID == habitID })
        else {
            pauseIntentLogger.error("no matching Activity for habitID=\(habitIDString, privacy: .public) (activities=\(Activity<HabitTimerAttributes>.activities.count))")
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
