import Foundation

/// A habit's repeat schedule — mirrors the RN app's four modes
/// (daily / specific days / times-per-week / every-X-days) from
/// SWIFT_REWRITE_INVENTORY.md's habit-creation flow.
///
/// `specificDays` uses 0 = Sunday ... 6 = Saturday, matching the existing
/// app's own dayjs-style convention (the RN app's `calendarService.ts` had
/// to convert this to EventKit's 1 = Sunday ... 7 = Saturday — worth
/// remembering when Calendar/Reminders integration lands in a later phase).
enum RepeatMode: Codable, Equatable {
    case daily
    case specificDays(Set<Int>)
    case timesPerWeek(Int)
    case everyXDays(Int)

    /// APP_REDESIGN_SPEC.md §12: terminology aligned to Apple's own
    /// Reminders app conventions ("Every Day", not "Daily") even though
    /// "Times per Week" isn't a literal Reminders option — Reminders has no
    /// flexible weekly-count mode, so this one is a Forge-specific addition
    /// styled in the same plain naming tone.
    var displayName: String {
        switch self {
        case .daily: "Every Day"
        case .specificDays: "Specific Days"
        case .timesPerWeek: "Times per Week"
        case .everyXDays: "Every X Days"
        }
    }
}
