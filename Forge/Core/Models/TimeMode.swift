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
    /// P1 Phase 2: the habit's time is anchored to a prayer (± an offset),
    /// recomputed daily from real prayer times rather than a fixed clock
    /// time. Calendar sync is disabled for this mode (Reminders-only), the
    /// same as `.everyXHours`/`.timesADay`, because the time shifts every day
    /// and `EKRecurrenceRule` can't represent that. See `PrayerAnchor`.
    case prayerRelative(PrayerAnchor)
}
