import Observation

/// Tiny deep-link bridge for "tapping the mood reminder notification opens
/// straight to the check-in card" (APP_REDESIGN_SPEC.md §13). There's no
/// separate mood screen to navigate to — the check-in card already lives
/// permanently near the top of Home (see `MoodCheckInCard`) — so "opens
/// straight to" is interpreted here as: switch to the Home tab if the user
/// was elsewhere, since the card is already immediately visible there
/// without any further scrolling/navigation. `MoodNotificationDelegate`
/// sets `pendingMoodCheckInPrompt` on a notification tap; `AppTabView`
/// observes it and flips back to `false` once it's acted on.
@MainActor
@Observable
final class MoodCheckInRouter {
    static let shared = MoodCheckInRouter()
    /// `nonisolated` deliberately — read from `MoodNotificationScheduler`
    /// and `MoodNotificationDelegate`, neither of which is main-actor
    /// isolated, unlike `shared`/`pendingMoodCheckInPrompt` above. It's an
    /// immutable `String` constant, so there's nothing actually requiring
    /// actor isolation.
    nonisolated static let notificationCategoryIdentifier = "MOOD_CHECK_IN"

    var pendingMoodCheckInPrompt = false

    private init() {}
}
