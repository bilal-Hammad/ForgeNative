import Foundation

/// A habit's time expressed *relative to a prayer* rather than a fixed clock
/// time — the new time-source concept from P1 Phase 2. E.g. a rawatib sunnah
/// "10 minutes before Dhuhr" is `PrayerAnchor(prayer: .dhuhr, offsetMinutes:
/// -10)`; a Fard prayer habit is the prayer's own adhan time,
/// `offsetMinutes: 0`.
///
/// The concrete clock time is **recomputed every day** from real
/// astronomical data (`PrayerTimeService`) against the user's location — it's
/// never a cached `Date`, because a prayer's time shifts daily. That daily
/// shift is exactly why Calendar sync is disabled for a prayer-relative habit
/// (an `EKRecurrenceRule` can only repeat at a fixed wall-clock time), the
/// same Reminders-only treatment `.everyXHours`/`.timesADay` already get.
struct PrayerAnchor: Codable, Equatable, Sendable {
    var prayer: PrayerName
    /// Signed minutes from the anchor prayer's adhan: negative = before,
    /// positive = after, `0` = exactly at the prayer.
    var offsetMinutes: Int

    init(prayer: PrayerName, offsetMinutes: Int = 0) {
        self.prayer = prayer
        self.offsetMinutes = offsetMinutes
    }

    /// A human label like "10 min before Dhuhr" / "At Fajr" / "5 min after
    /// Maghrib", for the habit form and list rows.
    var displayDescription: String {
        if offsetMinutes == 0 {
            return "At \(prayer.displayName)"
        }
        let magnitude = abs(offsetMinutes)
        let direction = offsetMinutes < 0 ? "before" : "after"
        return "\(magnitude) min \(direction) \(prayer.displayName)"
    }
}
