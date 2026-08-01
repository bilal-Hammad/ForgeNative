import Foundation

/// The single home for the user's prayer-related preferences, backed by
/// `UserDefaults` so both the SwiftUI Settings screen (`@AppStorage` on the
/// same keys) and non-view code (`PrayerTimeService`, the Phase 4 prayer
/// notification scheduler) read one shared source of truth.
///
/// Holds the calculation **method** (P1 Phase 2) and the per-prayer
/// notification **offsets** (P1 Phase 4).
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

    // MARK: - Notification offsets (Phase 4)

    private static func offsetsKey(for prayer: PrayerName) -> String {
        "prayerOffsets.\(prayer.rawValue)"
    }

    /// The single notification for a prayer fires at `adhan + iqamaDelay +
    /// prayerDuration` — i.e. once the congregational prayer has realistically
    /// finished — deliberately **not** at adhan time (redundant with the
    /// dedicated adhan apps users already have). Defaults per the spec:
    /// **Fajr 30 + 20 = 50 min** after adhan; **Dhuhr/Asr/Maghrib 10 + 15 =
    /// 25 min**. **Isha's default (10 + 15 = 25) is an assumption** — Bilal
    /// didn't specify it; it mirrors the Dhuhr/Asr/Maghrib pattern and is
    /// user-adjustable per prayer. These are properties of the *prayer* (how
    /// long after its adhan it's realistically prayed), so they're stored
    /// per-prayer and shared across every habit anchored to that prayer,
    /// edited from that habit's Notifications detail.
    static func defaultOffsets(for prayer: PrayerName) -> PrayerOffsets {
        switch prayer {
        case .fajr: return PrayerOffsets(iqamaDelayMinutes: 30, prayerDurationMinutes: 20)
        case .dhuhr, .asr, .maghrib, .isha: return PrayerOffsets(iqamaDelayMinutes: 10, prayerDurationMinutes: 15)
        }
    }

    static func offsets(for prayer: PrayerName) -> PrayerOffsets {
        guard let data = UserDefaults.standard.data(forKey: offsetsKey(for: prayer)),
              let decoded = try? JSONDecoder().decode(PrayerOffsets.self, from: data) else {
            return defaultOffsets(for: prayer)
        }
        return decoded
    }

    static func setOffsets(_ offsets: PrayerOffsets, for prayer: PrayerName) {
        guard let data = try? JSONEncoder().encode(offsets) else { return }
        UserDefaults.standard.set(data, forKey: offsetsKey(for: prayer))
    }
}

/// The two user-adjustable offsets that place a prayer's single notification
/// after its adhan (P1 Phase 4). Their sum is how many minutes after the adhan
/// the "did you pray / complete this?" notification fires.
struct PrayerOffsets: Codable, Equatable, Sendable {
    /// Minutes from adhan to iqama (the congregation standing up).
    var iqamaDelayMinutes: Int
    /// Minutes the prayer itself realistically takes after iqama.
    var prayerDurationMinutes: Int

    /// Total minutes after adhan that the notification fires.
    var totalMinutes: Int { iqamaDelayMinutes + prayerDurationMinutes }
}
