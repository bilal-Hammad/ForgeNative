import Foundation

/// Shared signal used by the Live Activity's interactive Stop button
/// (`StopTimerIntent`, in the `ForgeWidgets` extension) to tell the main
/// app which habit's timer to actually cancel, without ever launching the
/// app to do it directly.
///
/// **Why this exists instead of mutating `Completion.startedAt` straight
/// from the extension**: `StopTimerIntent` conforms to `LiveActivityIntent`
/// specifically so its `perform()` runs in the `ForgeWidgets` extension
/// process without opening `Forge` — that's the entire point of an
/// interactive Live Activity button. But `HabitRepository` is backed by a
/// SwiftData `ModelContainer` owned by `ForgeApp.init()`, in the main app's
/// process — not reachable from the extension. The alternative (moving the
/// whole persistent store into an App Group container so both processes
/// share one file) would touch the real on-device database location for
/// every existing habit/completion — a materially riskier change than this
/// feature needs. This type is the deliberately small compromise: only a
/// few bytes of shared `UserDefaults`, holding *which* habit(s) need
/// stopping, not the habit data itself.
///
/// The user-visible half of "stop" still happens immediately and directly
/// from the extension (`StopTimerIntent` ends the `Activity` itself via
/// `Activity<HabitTimerAttributes>.activities`, no App Group needed for
/// that lookup) — this signal only drives the *persisted* completion
/// catching up next time the app is opened, via
/// `HomeView.processPendingTimerStops()`. Same self-healing shape as
/// `checkTimerCompletions()` right next to it: cheap, checked on every
/// foreground, never relied on to fire instantly.
///
/// Compiled into both the `Forge` and `ForgeWidgets` targets — matches
/// `HabitTimerAttributes`/`HabitColor`'s existing direct-multi-target-file
/// pattern in this project rather than a shared framework for something
/// this small.
enum SharedTimerStopSignal {
    private static let appGroupID = "group.com.bilalhammad.forge.native"
    private static let key = "pendingTimerStopHabitIDs"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Called from `StopTimerIntent.perform()`, in the extension process.
    static func recordStop(habitID: UUID) {
        guard let defaults else { return }
        var ids = Set(defaults.stringArray(forKey: key) ?? [])
        ids.insert(habitID.uuidString)
        defaults.set(Array(ids), forKey: key)
    }

    /// Called from the main app on every foreground — returns and clears
    /// every pending habit ID. No concurrent-writer risk worth guarding
    /// against here (single user, one device, and a stale/lost signal
    /// self-heals anyway: the timer just keeps running until the next tap
    /// or foreground).
    static func drainPendingStops() -> [UUID] {
        guard let defaults else { return [] }
        let ids = defaults.stringArray(forKey: key) ?? []
        defaults.removeObject(forKey: key)
        return ids.compactMap(UUID.init)
    }
}
