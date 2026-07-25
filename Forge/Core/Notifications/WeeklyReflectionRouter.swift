import Observation

/// Tiny deep-link bridge for "tapping the weekly reflection notification
/// opens straight to the stats it's summarizing" (APP_REDESIGN_SPEC.md §13)
/// — same shape as `MoodCheckInRouter`, routed to the Progress tab instead
/// of Home, since that's where the underlying weekly completion-rate data
/// actually lives (`ProgressScreenView`'s Streak/Category Breakdown cards).
@MainActor
@Observable
final class WeeklyReflectionRouter {
    static let shared = WeeklyReflectionRouter()
    /// `nonisolated` for the same reason as `MoodCheckInRouter`'s — read
    /// from `WeeklyReflectionScheduler`/the notification delegate, neither
    /// of which is main-actor isolated.
    nonisolated static let notificationCategoryIdentifier = WeeklyReflectionScheduler.notificationCategoryIdentifier

    var pendingWeeklyReflectionPrompt = false

    private init() {}
}
