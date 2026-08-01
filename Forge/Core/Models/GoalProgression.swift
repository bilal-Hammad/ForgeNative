import Foundation

/// Automatic goal progression for a quantity habit (P1 Phase 5b): every
/// `intervalDays`, bump the habit's `goal` by `incrementAmount` and fire a
/// friendly notification. `nil` on a `Habit` means manual mode (the user edits
/// the goal themselves, anytime — always supported, and history-safe via
/// `Completion.goalAtCompletion` either way).
///
/// The bump *changes* `habit.goal` going forward on purpose; it never rewrites
/// past days, because each completion already snapshotted the goal in effect
/// when it was logged (Phase 5a).
struct GoalProgression: Codable, Equatable, Sendable {
    /// How much to add to the goal each interval (e.g. +10).
    var incrementAmount: Double
    /// Days between automatic increases (e.g. 30 for monthly).
    var intervalDays: Int

    init(incrementAmount: Double, intervalDays: Int) {
        self.incrementAmount = incrementAmount
        self.intervalDays = max(1, intervalDays)
    }
}
