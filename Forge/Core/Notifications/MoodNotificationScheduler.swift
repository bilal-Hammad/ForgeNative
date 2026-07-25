import Foundation
import UserNotifications

/// Schedules the single optional daily mood check-in reminder
/// (APP_REDESIGN_SPEC.md §13). Deliberately its own scheduler, not folded
/// into `HabitNotificationScheduler`'s per-habit budget/toggle system — §13
/// asks for mood reminders to be independently togglable, and there's only
/// ever at most one pending request for this feature (not per-habit), so
/// none of `HabitNotificationScheduler`'s multi-request/global-budget
/// machinery applies here.
enum MoodNotificationScheduler {
    static let identifier = "mood-check-in-reminder"

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

    /// Reschedules the one daily reminder at `hour:minute`, or cancels it
    /// if `enabled` is false. Safe to call any time the toggle or the
    /// chosen time changes (`SettingsView`'s Mood Check-In section).
    static func reschedule(enabled: Bool, hour: Int, minute: Int) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        let status = await currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "How are you feeling today?"
        content.body = "Take a second to log your mood — totally optional."
        content.sound = .default
        // Tapping this routes straight to the Home tab's mood check-in card
        // — see `MoodCheckInRouter` and `ForgeApp`'s
        // `UNUserNotificationCenterDelegate`.
        content.categoryIdentifier = MoodCheckInRouter.notificationCategoryIdentifier

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
