import Foundation
import UserNotifications

/// Schedules the weekly reflection notification (APP_REDESIGN_SPEC.md §13):
/// a once-a-week local notification (default Sunday evening, user-
/// configurable) summarizing that week's per-habit performance, framed
/// non-judgmentally for misses. Same independent-scheduler shape as
/// `MoodNotificationScheduler` — this is its own togglable feature, not
/// folded into `HabitNotificationScheduler`'s per-habit reminder budget.
///
/// **Content freshness, a deliberate scope decision:** the notification's
/// body depends on real weekly data that keeps changing all week, but there's
/// no server/remote-push or `BGTaskScheduler` background-refresh in this app
/// yet (both explicitly Phase 4+/5+ per APP_REDESIGN_SPEC.md §7 — "real
/// remote push... is where that gets used for real", not this pass). Rather
/// than build either of those just for this, `reschedule` computes fresh
/// content and re-schedules a **one-time** (`repeats: false`) trigger for
/// the next occurrence of the chosen weekday/time every time it's called —
/// call sites are the Settings toggle/time/weekday changing, and once on
/// every app foreground (`ForgeApp`), so content is as fresh as the last
/// time the user had the app open that week. A real user opens a habit
/// tracker daily by nature of what it tracks, so this converges in
/// practice; flagged here as a real, known limitation rather than silently
/// assumed to be perfect.
enum WeeklyReflectionScheduler {
    static let identifier = "weekly-reflection"
    static let notificationCategoryIdentifier = "WEEKLY_REFLECTION"

    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Cancels any pending reflection notification and, if `enabled`,
    /// computes fresh content from the last 7 days of real data and
    /// schedules one one-time notification for the next occurrence of
    /// `weekday`/`hour`/`minute`. `weekday` uses `Calendar`'s convention
    /// (1 = Sunday ... 7 = Saturday) — matches `DateComponents.weekday`
    /// directly, no translation needed.
    static func reschedule(
        habitRepository: HabitRepository,
        enabled: Bool,
        weekday: Int,
        hour: Int,
        minute: Int
    ) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        let status = await currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        guard let content = await buildContent(habitRepository: habitRepository) else { return }

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        // `repeats: false` is deliberate — see this type's doc comment.
        // `nextDate` under this trigger's own matching rules is always the
        // next upcoming occurrence, even if today already matches (it skips
        // to next week rather than firing again today), which is exactly
        // "next Sunday evening" whether called on a Tuesday or on Sunday
        // itself.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Bounded 7-day lookback only — never a full-history scan (Engineering
    /// Standards §1). Returns `nil` when there are no eligible habits at all
    /// (nothing to reflect on, so nothing gets scheduled).
    private static func buildContent(habitRepository: HabitRepository) async -> UNMutableNotificationContent? {
        let allHabits = (try? await habitRepository.fetchAll()) ?? []
        let eligibleHabits = allHabits.filter { !$0.isArchived && $0.weeklyReflectionEnabled }
        guard !eligibleHabits.isEmpty else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
        let completions = (try? await habitRepository.fetchCompletions(from: weekStart, to: today)) ?? []

        // Count of complete days in range, per habit — `isComplete` already
        // means "avoided" for a Bad habit and "did it" for Good/To-Do (see
        // `Completion`'s own doc comment), so a plain count is a fair
        // "win" tally across every category without special-casing Bad.
        var winsByHabit: [Habit.ID: Int] = [:]
        for completion in completions where completion.isComplete {
            winsByHabit[completion.habitID, default: 0] += 1
        }

        let daysInRange = 7
        let perfectWeek = eligibleHabits.first { (winsByHabit[$0.id] ?? 0) >= daysInRange }
        let mostMissed = eligibleHabits
            .map { habit in (habit, misses: daysInRange - (winsByHabit[habit.id] ?? 0)) }
            .filter { $0.misses > 0 }
            .max { $0.misses < $1.misses }

        let content = UNMutableNotificationContent()
        content.title = "Your Week in Review"
        if let perfectWeek {
            content.body = "You stuck with \(perfectWeek.title) all week — 7/7 days. Nice work."
        } else if let mostMissed {
            content.body = "You missed \(mostMissed.0.title) \(mostMissed.misses) time\(mostMissed.misses == 1 ? "" : "s") this week. Want to adjust the goal, or keep going?"
        } else {
            content.body = "Take a look at how your habits went this week."
        }
        content.sound = .default
        content.categoryIdentifier = notificationCategoryIdentifier
        return content
    }
}
