import Foundation
import UserNotifications

/// Applies due **automatic** goal increases (P1 Phase 5b). Self-healing
/// catch-up, same shape as `MilestoneEngine.runCatchUp()` — run on app
/// foreground, so a habit whose interval elapsed while the app was closed
/// still bumps. Bounded (a safety cap on bumps-per-run) per Engineering
/// standard #1.
///
/// A bump changes `habit.goal` going forward; past days are untouched because
/// each completion already snapshotted its goal (`Completion.goalAtCompletion`,
/// Phase 5a).
struct GoalProgressionEngine: Sendable {
    let habitRepository: HabitRepository
    let calendar: Calendar
    /// Never apply more than this many bumps in a single run (guards against a
    /// tiny interval / very old anchor looping).
    let maxBumpsPerRun: Int

    init(habitRepository: HabitRepository, calendar: Calendar = .current, maxBumpsPerRun: Int = 120) {
        self.habitRepository = habitRepository
        self.calendar = calendar
        self.maxBumpsPerRun = maxBumpsPerRun
    }

    func runCatchUp(now: Date = .now) async {
        let habits = (try? await habitRepository.fetchAll()) ?? []
        for habit in habits where !habit.isArchived {
            guard let progression = habit.goalProgression else { continue }

            // No anchor yet (progression just enabled without one) → initialize
            // to now, no retroactive bump for the habit's past.
            guard let anchor = habit.lastGoalIncreaseDate else {
                var updated = habit
                updated.lastGoalIncreaseDate = now
                try? await habitRepository.save(updated)
                continue
            }

            let anchorDay = calendar.startOfDay(for: anchor)
            let today = calendar.startOfDay(for: now)
            let elapsedDays = calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0
            let dueBumps = elapsedDays / progression.intervalDays
            guard dueBumps > 0 else { continue }

            let bumps = min(dueBumps, maxBumpsPerRun)
            var updated = habit
            updated.goal += progression.incrementAmount * Double(bumps)
            // Advance the anchor by exactly the applied whole intervals (not to
            // `now`), so partial progress toward the next interval is kept.
            updated.lastGoalIncreaseDate = calendar.date(byAdding: .day, value: bumps * progression.intervalDays, to: anchorDay) ?? now
            try? await habitRepository.save(updated)

            await notifyBump(for: updated)
        }
    }

    /// Friendly "your goal grew" notification — best-effort, only if
    /// notifications are authorized. Delivered immediately (nil trigger).
    private func notifyBump(for habit: Habit) async {
        let status = await HabitNotificationScheduler.currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = habit.title
        content.body = "Nice consistency! Your goal is now \(Self.format(habit.goal)) \(habit.unit.displayName.lowercased())."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "goal-bump-\(habit.id.uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
