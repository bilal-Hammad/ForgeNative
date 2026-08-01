import Foundation

/// The interactive state of a prayer-relative habit on one day (P1 Phase 3),
/// derived purely from its completion window, its current `Completion` (if
/// any), and `now`. Drives both the Home UI (whether the row is tappable /
/// how it reads) and the catch-up sweep (what to persist as missed). Pure and
/// unit-testable — no repository/location access.
enum PrayerDayState: Equatable, Sendable {
    /// The prayer's time hasn't arrived — not completable yet.
    case upcoming
    /// Window open, not completed — completable now.
    case open
    /// Isha past local midnight but before Fajr — completable, but "late".
    case openLate
    /// Completed within the window.
    case completed
    /// Window closed uncompleted — locked, no interaction, no retroactive
    /// completion.
    case missed

    /// Whether the user can tap to complete the prayer right now.
    var isCompletable: Bool { self == .open || self == .openLate }

    /// Whether the row should show as fully locked (no interactive options).
    var isMissedLocked: Bool { self == .missed }

    static func resolve(window: PrayerWindow?, completion: Completion?, now: Date = .now) -> PrayerDayState {
        // A real completion wins over everything.
        if completion?.isComplete == true { return .completed }
        // A persisted miss is authoritative — the window was evaluated when
        // its location was known, so a later location/schedule change can't
        // reopen it.
        if completion?.missed == true { return .missed }
        // No schedule/location available → degrade gracefully to completable
        // rather than blocking the user or forcing a false miss.
        guard let window else { return .open }
        if window.isUpcoming(at: now) { return .upcoming }
        if window.isClosed(at: now) { return .missed }
        return window.isPastPreferredTime(at: now) ? .openLate : .open
    }
}
