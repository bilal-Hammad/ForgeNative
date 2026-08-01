import Foundation

/// The single home for the user's prayer-related preferences, backed by
/// `UserDefaults` so both the SwiftUI Settings screen (`@AppStorage` on the
/// same keys) and non-view code (`PrayerTimeService`, the Phase 4 prayer
/// notification scheduler) read one shared source of truth.
///
/// Starts with the calculation **method** (P1 Phase 2); Phase 4 adds the
/// per-prayer notification offsets (iqama delay + prayer duration) here, the
/// same pattern.
enum PrayerPreferences {
    /// `@AppStorage` key for the calculation-method picker in `SettingsView`.
    static let calculationMethodKey = "prayerCalculationMethod"

    /// The user's chosen calculation method, defaulting to Muslim World League
    /// when unset or unrecognized.
    static var calculationMethod: PrayerCalculationMethod {
        get {
            guard let raw = UserDefaults.standard.string(forKey: calculationMethodKey),
                  let method = PrayerCalculationMethod(rawValue: raw) else {
                return .muslimWorldLeague
            }
            return method
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: calculationMethodKey) }
    }
}
