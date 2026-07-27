import ActivityKit
import AppIntents
import Foundation

/// Interactive Live Activity button — the Lock Screen/Dynamic Island
/// "Stop" control. Conforming to `LiveActivityIntent` (iOS 17+, instead of
/// plain `AppIntent`) is what makes `perform()` run directly in this
/// extension's own process when the button is tapped, without ever
/// launching or foregrounding the main `Forge` app — that's the entire
/// point of an interactive Live Activity button per Apple's design, and
/// matches the request's own "without opening the app" requirement.
///
/// Two distinct halves, deliberately different in how "immediate" they
/// are:
/// 1. **Ends the `Activity` itself, right here, right now** — found via
///    `Activity<HabitTimerAttributes>.activities`, the same static lookup
///    `HabitTimerCoordinator.reattachExistingActivities()` already uses
///    from the main app's process. This list is visible from either
///    process without needing an App Group. The Lock Screen banner
///    disappears the instant the button is tapped — no round trip to the
///    app required for that part.
/// 2. **Records the stop for the persisted `Completion.startedAt`** via
///    `SharedTimerStopSignal` — this can't happen directly here (SwiftData
///    isn't reachable from this process without a much larger, riskier
///    change; see that type's doc comment for the full reasoning) — the
///    main app catches it up next time it's foregrounded
///    (`HomeView.processPendingTimerStops()`), which then calls the exact
///    same `cancelTimer(for:)` a manual second tap on the row already
///    triggers today.
struct StopTimerIntent: LiveActivityIntent {
    // A computed property, not a stored `var` — Swift 6 strict
    // concurrency flags a stored static `var` here as nonisolated global
    // mutable state (it's never actually mutated, but the compiler can't
    // know that from a stored property alone). A computed property has no
    // storage to race on, satisfying the check without an
    // `nonisolated(unsafe)` escape hatch.
    static var title: LocalizedStringResource { "Stop Timer" }

    @Parameter(title: "Habit ID")
    var habitIDString: String

    init() {
        habitIDString = ""
    }

    init(habitID: UUID) {
        habitIDString = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let habitID = UUID(uuidString: habitIDString) else {
            return .result()
        }
        if let activity = Activity<HabitTimerAttributes>.activities.first(where: { $0.attributes.habitID == habitID }) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        SharedTimerStopSignal.recordStop(habitID: habitID)
        return .result()
    }
}
