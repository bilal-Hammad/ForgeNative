import Foundation
import UserNotifications

/// Schedules real local notifications for a habit's configured `TimeMode`
/// (APP_REDESIGN_SPEC.md §12), replacing the old UI-only toggle. The only
/// place that talks to `UNUserNotificationCenter` — every call site
/// (`HabitFormView` on save, archive/unarchive/delete in Home and Archived
/// Habits, the global Settings toggle) goes through this.
///
/// **Time-mode mapping:**
/// - `.fixedTime`: one daily repeating trigger at that exact hour/minute.
/// - `.everyXHours`: repeating triggers every X hours, but only within a
///   fixed **8:00–22:00 active window** — a deliberate default so a "every
///   1 hour" habit doesn't ping at 3am. There's no user-facing setting to
///   change this window yet; flagged as a reasonable follow-up, not
///   attempted in this pass.
/// - `.timesADay`: that many triggers spread evenly across the same
///   8:00–22:00 window.
/// - `.none`: nothing scheduled.
///
/// **Repeat-mode interaction:** `.specificDays` is the only `RepeatMode`
/// with real, predictable calendar days, so it's the only one that
/// restricts *which* weekdays a trigger fires on (one repeating weekly
/// trigger per selected weekday). `.daily`/`.timesPerWeek`/`.everyXDays` all
/// fall back to a plain "every day" reminder — this app has no due-date
/// engine that can say in advance which specific future day counts toward
/// a flexible weekly/interval target (nothing else in the app enforces
/// `repeatMode` yet either — Home shows every non-archived habit every day
/// regardless of its repeat mode — so this matches the app's existing
/// behavior, not a new inconsistency introduced here).
///
/// **Real iOS constraint, flagged rather than silently hit:**
/// `UNUserNotificationCenter` hard-caps an app at 64 *pending* requests
/// total, app-wide — not per-habit. A single repeating trigger only costs
/// one slot no matter how often it re-fires, but `.specificDays` × a short
/// `.everyXHours` interval can still multiply into dozens of slots for one
/// habit alone. This is guarded two ways: each habit is capped at
/// `maxRequestsPerHabit`, and `reschedule(for:globalNotificationsEnabled:)`
/// also checks the actual remaining app-wide budget (leaving a safety
/// margin under Apple's real ceiling) and truncates rather than let the OS
/// silently drop requests unpredictably past 64. At real scale (many habits
/// all wanting frequent reminders) local notifications alone can't fully
/// solve this — server-side push would be the real fix, and that's Phase
/// 4+ territory already flagged elsewhere in this spec, not attempted here.
enum HabitNotificationScheduler {
    static let activeWindowStartHour = 8
    static let activeWindowEndHour = 22
    static let maxRequestsPerHabit = 10
    /// Apple's real ceiling is 64 pending requests app-wide; this leaves a
    /// margin rather than scheduling right up to the edge.
    static let globalSafetyBudget = 60

    private static func identifierPrefix(for habitID: Habit.ID) -> String {
        "habit-reminder-\(habitID.uuidString)-"
    }

    private static func identifier(habitID: Habit.ID, index: Int) -> String {
        "\(identifierPrefix(for: habitID))\(index)"
    }

    // MARK: - Authorization

    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Requests permission if not yet determined; returns whether
    /// notifications are actually usable afterward. Safe to call
    /// repeatedly — does nothing but return the current state once the
    /// user has already answered (granted or denied), since iOS only ever
    /// shows the system prompt once.
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

    // MARK: - Scheduling

    /// Clears any previously scheduled reminders for this habit, then
    /// reschedules from scratch based on its current configuration. Call
    /// this any time a habit's notification-relevant state changes: saved
    /// from `HabitFormView`, archived (pauses immediately), unarchived
    /// (resumes), or the global Settings toggle changes.
    static func reschedule(for habit: Habit, globalNotificationsEnabled: Bool) async {
        removeAll(for: habit.id)

        guard globalNotificationsEnabled, habit.notificationsEnabled, !habit.isArchived, habit.timeMode != .none else {
            return
        }
        let status = await currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        var requests = buildRequests(for: habit)
        guard !requests.isEmpty else { return }

        let budget = await remainingGlobalBudget(excluding: habit.id)
        guard budget > 0 else { return }
        if requests.count > budget {
            requests = Array(requests.prefix(budget))
        }

        let center = UNUserNotificationCenter.current()
        for request in requests {
            try? await center.add(request)
        }
    }

    /// Cancels every pending reminder for this habit — used on archive and
    /// delete, and as the first step of every `reschedule` call.
    static func removeAll(for habitID: Habit.ID) {
        let identifiers = (0..<maxRequestsPerHabit).map { identifier(habitID: habitID, index: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func remainingGlobalBudget(excluding habitID: Habit.ID) async -> Int {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let prefix = identifierPrefix(for: habitID)
        let othersCount = pending.filter { !$0.identifier.hasPrefix(prefix) }.count
        return max(0, globalSafetyBudget - othersCount)
    }

    private static func buildRequests(for habit: Habit) -> [UNNotificationRequest] {
        let times = fireTimes(for: habit.timeMode)
        guard !times.isEmpty else { return [] }
        let weekdays = weekdaysToSchedule(for: habit.repeatMode)

        var requests: [UNNotificationRequest] = []
        outer: for time in times {
            if let weekdays {
                for weekday in weekdays {
                    guard requests.count < maxRequestsPerHabit else { break outer }
                    var components = DateComponents()
                    components.hour = time.hour
                    components.minute = time.minute
                    components.weekday = weekday + 1 // RepeatMode: 0 = Sunday; Calendar/UNCalendarNotificationTrigger: 1 = Sunday
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    requests.append(makeRequest(habit: habit, index: requests.count, trigger: trigger))
                }
            } else {
                guard requests.count < maxRequestsPerHabit else { break outer }
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                requests.append(makeRequest(habit: habit, index: requests.count, trigger: trigger))
            }
        }
        return requests
    }

    private static func makeRequest(habit: Habit, index: Int, trigger: UNCalendarNotificationTrigger) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = habit.title
        content.body = reminderBody(for: habit)
        content.sound = .default
        return UNNotificationRequest(identifier: identifier(habitID: habit.id, index: index), content: content, trigger: trigger)
    }

    private static func reminderBody(for habit: Habit) -> String {
        switch habit.category {
        case .good: "Time to \(habit.title.lowercased())."
        case .bad: "Stay on track — skip \(habit.title.lowercased()) today."
        case .todo: "Don't forget: \(habit.title)."
        }
    }

    private static func weekdaysToSchedule(for repeatMode: RepeatMode) -> [Int]? {
        if case .specificDays(let days) = repeatMode, !days.isEmpty {
            return Array(days)
        }
        return nil
    }

    private struct FireTime {
        let hour: Int
        let minute: Int
    }

    private static func fireTimes(for timeMode: TimeMode) -> [FireTime] {
        switch timeMode {
        case .none:
            return []
        case .fixedTime(let date):
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            return [FireTime(hour: components.hour ?? 9, minute: components.minute ?? 0)]
        case .everyXHours(let interval):
            guard interval > 0 else { return [] }
            var times: [FireTime] = []
            var hour = activeWindowStartHour
            while hour <= activeWindowEndHour, times.count < maxRequestsPerHabit {
                times.append(FireTime(hour: hour, minute: 0))
                hour += interval
            }
            return times
        case .timesADay(let count):
            guard count > 0 else { return [] }
            let cappedCount = min(count, maxRequestsPerHabit)
            let windowMinutes = (activeWindowEndHour - activeWindowStartHour) * 60
            let startMinutes = activeWindowStartHour * 60
            return (0..<cappedCount).map { i in
                let totalMinutes = startMinutes + Int(Double(windowMinutes) * Double(i) / Double(cappedCount))
                return FireTime(hour: totalMinutes / 60, minute: totalMinutes % 60)
            }
        }
    }
}
