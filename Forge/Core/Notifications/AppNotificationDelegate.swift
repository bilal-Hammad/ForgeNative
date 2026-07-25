import UserNotifications

/// The app's only `UNUserNotificationCenterDelegate` — set once in
/// `ForgeApp.init()`. Two jobs, shared across every notification category
/// that needs them: let a notification actually show as a banner if it
/// fires while the app is already in the foreground (iOS suppresses
/// foreground notifications by default), and route a tap on it to the
/// right tab via that feature's own router (`MoodCheckInRouter` → Home,
/// `WeeklyReflectionRouter` → Progress). `HabitNotificationScheduler`
/// doesn't need either — its reminders have no in-app destination beyond
/// "open the app," which is the system default with no delegate at all.
///
/// Originally named `MoodNotificationDelegate` when mood was the only
/// category it handled — renamed once a second category (weekly
/// reflection) needed the same delegate, since a mood-specific name on the
/// app's one shared delegate would read as misleading to a future reader.
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.notification.request.content.categoryIdentifier {
        case MoodCheckInRouter.notificationCategoryIdentifier:
            await MainActor.run {
                MoodCheckInRouter.shared.pendingMoodCheckInPrompt = true
            }
        case WeeklyReflectionRouter.notificationCategoryIdentifier:
            await MainActor.run {
                WeeklyReflectionRouter.shared.pendingWeeklyReflectionPrompt = true
            }
        default:
            break
        }
    }
}
