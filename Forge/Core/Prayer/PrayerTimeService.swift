import Foundation
import Adhan

// Adhan's `CalculationMethod`/`Madhab` are trivial immutable value enums (no
// associated values, no reference storage) — genuinely `Sendable`, just not
// declared so in Adhan 1.5.0. Retroactive `@unchecked` conformance lets the
// `Sendable` `PrayerTimeService` store them without leaking a concurrency
// hole. If a future Adhan version adds its own `Sendable` conformance, delete
// these two lines (the compiler will flag them as redundant).
extension Adhan.CalculationMethod: @retroactive @unchecked Sendable {}
extension Adhan.Madhab: @retroactive @unchecked Sendable {}

/// Computes prayer times + resolves a prayer-relative habit's concrete clock
/// time for a given day/location (P1 Phase 2). The single boundary that
/// touches the Adhan package — everything else works against the Adhan-free
/// `PrayerSchedule`/`PrayerAnchor`/`Coordinate` value types.
///
/// API verified against Adhan Swift 1.5.0 source before use (standing "verify
/// APIs" rule): `PrayerTimes(coordinates:date:calculationParameters:)` is a
/// **failable** init taking `DateComponents`; `.fajr/.sunrise/.dhuhr/.asr/
/// .maghrib/.isha` are `Date`; madhab is set via `params.madhab`.
protocol PrayerTimeService: Sendable {
    /// The five prayer times (+ sunrise) for `date`'s calendar day at
    /// `coordinate`. `nil` only if Adhan can't compute (extreme latitude /
    /// invalid input) — callers treat that as "no prayer schedule available".
    func schedule(for date: Date, at coordinate: Coordinate) -> PrayerSchedule?

    /// The concrete clock time a prayer-relative habit fires on `date`:
    /// the anchor prayer's adhan shifted by the anchor's signed offset.
    func resolvedTime(for anchor: PrayerAnchor, on date: Date, at coordinate: Coordinate) -> Date?
}

/// Concrete Adhan-backed implementation.
///
/// **Asr madhab: Shafi'i** (explicit product decision — TASKS.md). Calculation
/// **method defaults to Muslim World League** — a sensible global default;
/// the method affects Fajr/Isha twilight angles and is a reasonable candidate
/// for a future user/region setting (flagged, not a silent choice).
struct AdhanPrayerTimeService: PrayerTimeService {
    var method: CalculationMethod
    var madhab: Madhab
    /// Used to derive the year/month/day Adhan needs. Defaults to
    /// `Calendar.current` so "today" is the user's local day; tests inject a
    /// fixed-timezone calendar for deterministic assertions.
    var calendar: Calendar

    init(
        method: CalculationMethod = .muslimWorldLeague,
        madhab: Madhab = .shafi,
        calendar: Calendar = .current
    ) {
        self.method = method
        self.madhab = madhab
        self.calendar = calendar
    }

    func schedule(for date: Date, at coordinate: Coordinate) -> PrayerSchedule? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var params = method.params
        params.madhab = madhab
        guard let times = PrayerTimes(
            coordinates: Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude),
            date: components,
            calculationParameters: params
        ) else { return nil }

        return PrayerSchedule(
            day: calendar.startOfDay(for: date),
            fajr: times.fajr,
            sunrise: times.sunrise,
            dhuhr: times.dhuhr,
            asr: times.asr,
            maghrib: times.maghrib,
            isha: times.isha
        )
    }

    func resolvedTime(for anchor: PrayerAnchor, on date: Date, at coordinate: Coordinate) -> Date? {
        guard let schedule = schedule(for: date, at: coordinate) else { return nil }
        return schedule.time(for: anchor.prayer).addingTimeInterval(Double(anchor.offsetMinutes) * 60)
    }
}
