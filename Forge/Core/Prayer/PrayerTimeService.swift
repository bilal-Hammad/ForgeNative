import Foundation
import Adhan

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
/// **Asr madhab: Shafi'i** — a fixed product decision (TASKS.md), hardcoded
/// below rather than exposed. The calculation **method is user-configurable**
/// (`PrayerPreferences`, a Settings picker) with **Muslim World League** as
/// the default, since the method affects Fajr/Isha twilight angles and the
/// "right" one varies by region. Stores the Adhan-free `PrayerCalculationMethod`
/// (mapped to Adhan's `CalculationMethod` internally), so this `Sendable`
/// service holds no Adhan value type.
struct AdhanPrayerTimeService: PrayerTimeService {
    var method: PrayerCalculationMethod
    /// Used to derive the year/month/day Adhan needs. Defaults to
    /// `Calendar.current` so "today" is the user's local day; tests inject a
    /// fixed-timezone calendar for deterministic assertions.
    var calendar: Calendar

    init(
        method: PrayerCalculationMethod = .muslimWorldLeague,
        calendar: Calendar = .current
    ) {
        self.method = method
        self.calendar = calendar
    }

    /// A service configured from the user's saved calculation-method
    /// preference — the entry point non-view code (Phase 3 catch-up, Phase 4
    /// notifications) uses so it always reflects the Settings choice.
    static func fromPreferences() -> AdhanPrayerTimeService {
        AdhanPrayerTimeService(method: PrayerPreferences.calculationMethod)
    }

    func schedule(for date: Date, at coordinate: Coordinate) -> PrayerSchedule? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var params = method.adhanMethod.params
        params.madhab = .shafi
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

/// The one place the Adhan-free `PrayerCalculationMethod` maps to Adhan's own
/// `CalculationMethod` — kept in this Adhan-importing file so the enum itself
/// stays dependency-free.
private extension PrayerCalculationMethod {
    var adhanMethod: Adhan.CalculationMethod {
        switch self {
        case .muslimWorldLeague: .muslimWorldLeague
        case .egyptian: .egyptian
        case .karachi: .karachi
        case .ummAlQura: .ummAlQura
        case .dubai: .dubai
        case .moonsightingCommittee: .moonsightingCommittee
        case .northAmerica: .northAmerica
        case .kuwait: .kuwait
        case .qatar: .qatar
        case .singapore: .singapore
        case .tehran: .tehran
        case .turkey: .turkey
        }
    }
}
