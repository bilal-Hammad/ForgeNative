import UserNotifications

/// The app's only `UNUserNotificationCenterDelegate` — set once in
/// `ForgeApp.init()`. Two jobs: let the mood reminder actually show as a
/// banner if it fires while the app is already in the foreground (iOS
/// suppresses foreground notifications by default), and route a tap on it
/// through `MoodCheckInRouter` to the Home tab. `HabitNotificationScheduler`
/// doesn't need either — its reminders have no in-app destination beyond
/// "open the app," which is the system default with no delegate at all.
final class MoodNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
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
        guard response.notification.request.content.categoryIdentifier == MoodCheckInRouter.notificationCategoryIdentifier else {
            return
        }
        await MainActor.run {
            MoodCheckInRouter.shared.pendingMoodCheckInPrompt = true
        }
    }
}
