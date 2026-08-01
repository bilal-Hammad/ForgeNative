import Foundation

/// Resolves the strict completion window for a prayer on a given day, from the
/// day's (and, for Isha, the next day's) prayer schedule. Verified against
/// real fiqh sources (IslamQA / SeekersGuidance) — P1 Phase 3:
///
/// - **Fajr**: adhan → sunrise.
/// - **Dhuhr**: adhan → Asr start.
/// - **Asr** (Shafi'i calc): start → Maghrib.
/// - **Maghrib**: adhan → Isha start.
/// - **Isha**: adhan → **next day's** true dawn / Fajr (the valid outer
///   boundary), with a `preferredEnd` at local midnight after which it reads
///   as "late" but stays completable. This is also the window a night prayer
///   (Witr / Qiyam al-layl) uses — Isha → Fajr, deliberately spanning
///   midnight, handled explicitly rather than assuming same-day boundaries.
///
/// A prayer-relative habit's window is its **anchor prayer's** window
/// regardless of the anchor's minute offset (a "10 min before Dhuhr" sunnah
/// and a dhikr-after-Dhuhr both complete within Dhuhr's window) — the offset
/// only shifts the notification/display time, not the completable window.
struct PrayerWindowResolver: Sendable {
    let service: PrayerTimeService
    let calendar: Calendar

    init(service: PrayerTimeService, calendar: Calendar = .current) {
        self.service = service
        self.calendar = calendar
    }

    /// The completion window for `prayer` on `day` at `coordinate`, or `nil`
    /// if the schedule can't be computed (e.g. extreme latitude).
    func window(for prayer: PrayerName, on day: Date, at coordinate: Coordinate) -> PrayerWindow? {
        guard let today = service.schedule(for: day, at: coordinate) else { return nil }

        switch prayer {
        case .fajr:
            return PrayerWindow(prayer: .fajr, start: today.fajr, end: today.sunrise)
        case .dhuhr:
            return PrayerWindow(prayer: .dhuhr, start: today.dhuhr, end: today.asr)
        case .asr:
            return PrayerWindow(prayer: .asr, start: today.asr, end: today.maghrib)
        case .maghrib:
            return PrayerWindow(prayer: .maghrib, start: today.maghrib, end: today.isha)
        case .isha:
            // Cross-midnight: ends at the *next* calendar day's Fajr; the
            // preferred-time boundary is the start of that next day.
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                  let tomorrow = service.schedule(for: nextDay, at: coordinate) else {
                return nil
            }
            let midnight = calendar.startOfDay(for: nextDay)
            return PrayerWindow(prayer: .isha, start: today.isha, end: tomorrow.fajr, preferredEnd: midnight)
        }
    }

    /// Convenience for a prayer-relative habit's anchor.
    func window(for anchor: PrayerAnchor, on day: Date, at coordinate: Coordinate) -> PrayerWindow? {
        window(for: anchor.prayer, on: day, at: coordinate)
    }
}
