import Foundation

/// Shared signal for the Live Activity's pause/resume button
/// (`ToggleTimerPauseIntent`, in the `ForgeWidgets` extension) to tell the
/// main app the timer's new accumulated-elapsed state, without launching the
/// app. Exactly the same mechanism and reasoning as `SharedTimerStopSignal`
/// (a few bytes of App-Group `UserDefaults`, not the SwiftData store — the
/// extension can't reach the store): the button updates the `Activity` itself
/// immediately for instant feedback, and this signal only drives the
/// *persisted* `Completion` catching up on the next foreground
/// (`HomeView.processPendingTimerSignals()`).
///
/// The extension is the source of truth for the exact moment of the tap, so
/// it writes the fully-resolved new state (banked elapsed + the running
/// segment's start, or nil while paused) rather than an event for the app to
/// re-derive — avoids any drift between the two processes' clocks.
///
/// Stored as a plist-safe `[habitIDString: [accumulatedElapsed,
/// runStartedAtEpoch]]` dictionary; `runStartedAtEpoch < 0` encodes "paused"
/// (`runStartedAt == nil`). Compiled into both targets, matching
/// `SharedTimerStopSignal`/`HabitTimerAttributes`/`HabitColor`.
enum SharedTimerPauseSignal {
    private static let appGroupID = "group.com.bilalhammad.forge.native"
    private static let key = "pendingTimerPauseStates"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Called from `ToggleTimerPauseIntent.perform()`, in the extension.
    /// `runStartedAt == nil` means the timer is now paused.
    static func record(habitID: UUID, accumulatedElapsed: TimeInterval, runStartedAt: Date?) {
        guard let defaults else { return }
        var dict = (defaults.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
        dict[habitID.uuidString] = [accumulatedElapsed, runStartedAt?.timeIntervalSince1970 ?? -1]
        defaults.set(dict, forKey: key)
    }

    /// Called from the main app on every foreground — returns and clears
    /// every pending state change. Same single-user, self-healing
    /// no-concurrent-writer reasoning as `SharedTimerStopSignal.drainPendingStops`.
    static func drain() -> [(habitID: UUID, accumulatedElapsed: TimeInterval, runStartedAt: Date?)] {
        guard let defaults else { return [] }
        let dict = (defaults.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
        defaults.removeObject(forKey: key)
        return dict.compactMap { keyString, values in
            guard let id = UUID(uuidString: keyString), values.count == 2 else { return nil }
            let runStartedAt = values[1] < 0 ? nil : Date(timeIntervalSince1970: values[1])
            return (id, values[0], runStartedAt)
        }
    }
}
