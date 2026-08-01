import Foundation

/// The user-selectable prayer-time calculation method (P1 Phase 2, made
/// user-configurable per Bilal's decision 2026-08-01). Different authorities
/// use different twilight angles for Fajr/Isha, so the "correct" times vary by
/// region — hence a Settings picker rather than a hardcoded value, with
/// **Muslim World League** as the sensible global default.
///
/// Deliberately Adhan-free (a plain `String`-backed enum) so it persists via
/// `@AppStorage`/`UserDefaults` and is read by non-view code without importing
/// Adhan — `PrayerTimeService` is the only place that maps this to Adhan's own
/// `CalculationMethod`. Adhan's `.other` (a manual-angles escape hatch) is
/// intentionally omitted: it isn't a meaningful user-pickable preset.
enum PrayerCalculationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case muslimWorldLeague
    case egyptian
    case karachi
    case ummAlQura
    case dubai
    case moonsightingCommittee
    case northAmerica
    case kuwait
    case qatar
    case singapore
    case tehran
    case turkey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muslimWorldLeague: "Muslim World League"
        case .egyptian: "Egyptian General Authority"
        case .karachi: "University of Islamic Sciences, Karachi"
        case .ummAlQura: "Umm al-Qura, Makkah"
        case .dubai: "Dubai"
        case .moonsightingCommittee: "Moonsighting Committee"
        case .northAmerica: "ISNA (North America)"
        case .kuwait: "Kuwait"
        case .qatar: "Qatar"
        case .singapore: "Singapore"
        case .tehran: "Tehran"
        case .turkey: "Diyanet (Turkey)"
        }
    }
}
