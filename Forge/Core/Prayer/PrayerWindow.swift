import Foundation

/// The strict completion window for a prayer-relative habit (P1 Phase 3). A
/// prayer's habit can only be completed while its window is open; once the
/// window closes uncompleted, the day is auto-marked missed and locked (no
/// retroactive completion). Windows are verified against real fiqh sources
/// (IslamQA / SeekersGuidance) — see `PrayerWindowResolver` for the exact
/// per-prayer boundaries.
struct PrayerWindow: Equatable, Sendable {
    let prayer: PrayerName
    let start: Date
    let end: Date
    /// Isha only: local midnight. After this the *preferred* time has passed
    /// (surface a distinct "late" indicator) but the prayer is **still
    /// completable** until `end` (the following Fajr / true dawn). `nil` for
    /// every other prayer.
    let preferredEnd: Date?

    init(prayer: PrayerName, start: Date, end: Date, preferredEnd: Date? = nil) {
        self.prayer = prayer
        self.start = start
        self.end = end
        self.preferredEnd = preferredEnd
    }

    /// Completable right now (within `[start, end)`).
    func isOpen(at now: Date = .now) -> Bool { now >= start && now < end }

    /// The window has fully closed — this is the auto-miss / lock condition.
    func isClosed(at now: Date = .now) -> Bool { now >= end }

    /// Not yet started (the prayer's time hasn't arrived).
    func isUpcoming(at now: Date = .now) -> Bool { now < start }

    /// Isha past local midnight but before Fajr: still completable, but the
    /// preferred time has passed — drives the distinct "late" visual /
    /// notification indicator without locking the habit.
    func isPastPreferredTime(at now: Date = .now) -> Bool {
        guard let preferredEnd else { return false }
        return now >= preferredEnd && now < end
    }
}
