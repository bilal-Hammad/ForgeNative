import Foundation

/// The five daily obligatory prayers, used as the anchor for a
/// prayer-relative habit's timing (P1 "StoreKit + Islamic Template",
/// Phase 2). Deliberately Adhan-free (a plain `String`-backed enum) so it can
/// live on the `Habit` model, be JSON-persisted, and cross into the widget/
/// notification code without any target depending on the Adhan package —
/// only `PrayerTimeService` translates these to Adhan's own `Prayer` type.
///
/// Sunrise is intentionally not here: it's a window *boundary* (Fajr's outer
/// edge), computed as part of the schedule, never something a habit anchors
/// to.
enum PrayerName: String, Codable, CaseIterable, Identifiable, Sendable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }
}
