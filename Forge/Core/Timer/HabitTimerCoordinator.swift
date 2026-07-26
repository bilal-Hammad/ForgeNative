// `@preconcurrency` — ActivityKit's `Activity.end(_:dismissalPolicy:)` is
// `nonisolated` but not fully Sendable-audited by Apple as of this SDK,
// which trips Swift 6's strict "sending a main-actor-isolated value into a
// nonisolated call" check even though `Activity<HabitTimerAttributes>` is
// genuinely safe to use this way (it's a short-lived local handle, never
// shared/mutated concurrently). This suppresses that specific over-strict
// check for symbols imported from ActivityKit, matching Apple's own stated
// purpose for `@preconcurrency import` (bridging not-yet-audited system
// frameworks), rather than silencing Swift 6 concurrency checking
// project-wide.
@preconcurrency import ActivityKit
import Foundation

/// Owns the *ephemeral* plumbing for a running time-unit habit's timer —
/// the Live Activity handle and the one-shot "goal reached" scheduling.
/// Deliberately does **not** own persistence, completion feedback, or
/// HealthKit write-back — those stay in `HomeView`, matching this
/// project's existing split (`HealthKitService`/`MilestoneEngine` are also
/// separate from the view code that triggers them). The actual source of
/// truth for "is this habit's timer running" is `Completion.startedAt`
/// (persisted, survives relaunch) plus `habit.goal`/`habit.unit` — not
/// anything in this class — so a fresh process can always re-derive a
/// row's timer state for rendering without needing this coordinator at
/// all; this class only needs to catch up its own Live-Activity bookkeeping
/// on launch (see `reattachExistingActivities`).
///
/// `.shared` singleton, matching `MoodCheckInRouter`/`WeeklyReflectionRouter`'s
/// existing pattern for a small cross-cutting app-wide coordinator — not
/// dependency-injected via `Environment` the way repositories are, since
/// nothing needs a substitute implementation for previews/tests (the
/// `-uiTesting` fixture just runs against real `ActivityKit`, which no-ops
/// safely when Live Activities aren't enabled/available).
@MainActor
@Observable
final class HabitTimerCoordinator {
    static let shared = HabitTimerCoordinator()
    private init() {}

    private var activities: [UUID: Activity<HabitTimerAttributes>] = [:]
    private var scheduledCompletions: [UUID: Task<Void, Never>] = [:]

    /// Best-effort — Live Activities can be unavailable (user disabled them
    /// in Settings, Simulator without support, etc.). The in-app timer UI
    /// (driven entirely by persisted `Completion.startedAt`) works
    /// identically either way, so a failure/denial here never blocks the
    /// actual feature.
    func startLiveActivity(habitID: UUID, title: String, iconSystemName: String, color: HabitColor, start: Date, end: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = HabitTimerAttributes(
            habitID: habitID,
            habitTitle: title,
            iconSystemName: iconSystemName,
            color: color,
            startDate: start
        )
        let content = ActivityContent(state: HabitTimerAttributes.ContentState(endDate: end), staleDate: end)
        guard let activity = try? Activity.request(attributes: attributes, content: content) else { return }
        activities[habitID] = activity
    }

    /// `completed: true` briefly keeps the final state visible (matching
    /// Apple's own Timer app behavior of a short "Time's up" linger) before
    /// the system dismisses it; `completed: false` (the timer was
    /// cancelled by a second tap, or superseded by a long-press force-
    /// complete) dismisses immediately with no lingering state to show.
    func endLiveActivity(habitID: UUID, completed: Bool) {
        cancelScheduledCompletion(habitID: habitID)
        guard let activity = activities.removeValue(forKey: habitID) else { return }
        Task {
            await activity.end(nil, dismissalPolicy: completed ? .after(.now.addingTimeInterval(3)) : .immediate)
        }
    }

    /// A single non-repeating sleep to the goal's end instant — not a
    /// per-second poll — purely to trigger the one "goal reached" side
    /// effect (completion feedback, persistence, HealthKit write) at
    /// roughly the right moment while the app is foregrounded. This is
    /// deliberately *not* the mechanism relied on for correctness: if the
    /// app is backgrounded/killed before this fires, `HomeView`'s
    /// catch-up sweep (driven by the same persisted `startedAt`, checked on
    /// every foreground/appear) is what actually guarantees the habit gets
    /// marked complete — this is just what makes it feel instant while the
    /// user is still watching.
    func scheduleCompletion(habitID: UUID, at date: Date, onComplete: @escaping () async -> Void) {
        scheduledCompletions[habitID]?.cancel()
        scheduledCompletions[habitID] = Task {
            let interval = date.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled else { return }
            await onComplete()
        }
    }

    func cancelScheduledCompletion(habitID: UUID) {
        scheduledCompletions[habitID]?.cancel()
        scheduledCompletions[habitID] = nil
    }

    /// Re-populates `activities` from ActivityKit's own system-tracked
    /// state on a fresh launch. `activities` itself always starts empty in
    /// a new process, but a Live Activity started in a *previous* process
    /// (then killed) is still genuinely running — tracked by the system,
    /// not this in-memory dictionary — so without this, `endLiveActivity`
    /// would have nothing to find and dismiss later. Call once at launch.
    func reattachExistingActivities() {
        for activity in Activity<HabitTimerAttributes>.activities {
            activities[activity.attributes.habitID] = activity
        }
    }
}
