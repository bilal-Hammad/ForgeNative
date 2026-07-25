import Foundation

/// APP_REDESIGN_SPEC.md §12: Apple's Reminders app splits this into "Time"
/// (a plain fixed-time picker) vs. "Suggested Time" (ML-based, not built in
/// v1 — flagged as a Phase 5+ enhancement). "Every X Hours" / "X Times a
/// Day" are Forge-specific extensions beyond what Reminders offers, for
/// interval-based habits like water-drinking.
enum TimeMode: Codable, Equatable {
    case none
    case fixedTime(Date)
    case everyXHours(Int)
    case timesADay(Int)
}
