import Foundation

/// The computed prayer times for one calendar day at one location. Adhan-free
/// value type (the service converts Adhan's output into this), so the rest of
/// the app — completion windows (Phase 3), notifications (Phase 4), UI —
/// works against plain `Date`s without importing Adhan.
struct PrayerSchedule: Equatable, Sendable {
    /// Start of the day these times were computed for.
    let day: Date
    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date

    /// The adhan time for one of the five prayers.
    func time(for prayer: PrayerName) -> Date {
        switch prayer {
        case .fajr: fajr
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }
}
