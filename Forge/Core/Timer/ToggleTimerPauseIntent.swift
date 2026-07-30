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
        // `.error` level so idevicesyslog/log stream reliably capture it —
        // the whole point is proving whether this runs at all when Bilal taps
        // the Lock Screen pause button (an unobservable path otherwise).
        pauseIntentLogger.error("perform() ENTERED process=\(ProcessInfo.processInfo.processName, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier) habitID=\(habitIDString, privacy: .public) activitiesVisible=\(Activity<HabitTimerAttributes>.activities.count)")
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
        // Banked elapsed is the same value in both branches (total elapsed at
        // the moment of the tap); only whether a run segment is live differs.
        let bankedElapsed: TimeInterval

        if state.isPaused {
            // Resume: rebuild the timeline so it ends `remaining` from now,
            // re-anchoring `effectiveStartDate` back by the banked time, and
            // clear `pausedAt` so the system ticks it again.
            let remaining = max(0, state.endDate.timeIntervalSince(state.pausedAt ?? now))
            let newEnd = now.addingTimeInterval(remaining)
            newState = HabitTimerAttributes.ContentState(
                effectiveStartDate: newEnd.addingTimeInterval(-goalDuration),
                endDate: newEnd,
                pausedAt: nil
            )
            bankedElapsed = max(0, goalDuration - remaining)
            signalRunStartedAt = now
        } else {
            // Pause: freeze the countdown at `now` via `pauseTime` — the
            // timeline is untouched, the system just stops advancing it.
            newState = HabitTimerAttributes.ContentState(
                effectiveStartDate: state.effectiveStartDate,
                endDate: state.endDate,
                pausedAt: now
            )
            bankedElapsed = max(0, now.timeIntervalSince(state.effectiveStartDate))
            signalRunStartedAt = nil
        }

        pauseIntentLogger.error("about to update Activity → paused=\(newState.isPaused) banked=\(bankedElapsed, format: .fixed(precision: 1))")
        await activity.update(ActivityContent(state: newState, staleDate: newState.isPaused ? nil : newState.endDate))
        SharedTimerPauseSignal.record(habitID: habitID, accumulatedElapsed: bankedElapsed, runStartedAt: signalRunStartedAt)
        pauseIntentLogger.error("Activity.update returned; signal recorded")
        return .result()
    }
}
