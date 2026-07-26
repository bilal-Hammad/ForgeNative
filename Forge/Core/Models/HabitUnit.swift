import Foundation

/// The closed unit set, derived from the real RN app's actual template data
/// (`src/templates/seed.ts` + `healthTemplates.ts`), not guessed — see the
/// audit reported during this pass. `times` (18 templates) and "no unit at
/// all" (96 templates) were the same underlying concept represented two
/// inconsistent ways in that data; both consolidate to `.count` here. The
/// single Gratitude-only `things` unit also folds into `.count` rather than
/// adding a picker option used by exactly one habit.
///
/// `mmHg` / `milligramsPerDeciliter` / `percent` are internal-only: they
/// only ever appear on HealthKit-locked templates (Blood Pressure, Blood
/// Glucose, Body Fat %), and per §12's editability rule those habits have
/// their unit locked/read-only and never show this picker at all. They're
/// real enum cases (so those templates' data is still strongly typed) but
/// excluded from `pickerOptions`, so a manually-created habit can never
/// select them.
enum HabitUnit: String, Codable, CaseIterable, Identifiable {
    case count, minutes, hours, steps, glasses, calories, grams, milligrams, milliliters, servings, flights, words, kilograms, centimeters
    case mmHg, milligramsPerDeciliter, percent

    var id: String { rawValue }

    /// Gates the native timer interaction (replacing tap-to-increment
    /// entirely for these habits — see `HomeView.handleTap`): a duration
    /// goal has no coherent "increment by a fixed step" meaning the way a
    /// count/quantity goal does. Generic on the unit case itself, not on
    /// any specific habit/template — applies equally to a HealthKit-backed
    /// preset (Run, Yoga) and a manually-created custom habit that happens
    /// to use minutes/hours.
    var isTimeBased: Bool {
        self == .minutes || self == .hours
    }

    /// Seconds per one unit of `self` — converts a real elapsed
    /// `TimeInterval` into this habit's own `goal`/`count` terms. Only
    /// meaningful for `isTimeBased` units.
    var secondsPerUnit: TimeInterval {
        switch self {
        case .hours: 3600
        case .minutes: 60
        default: 1
        }
    }

    static var pickerOptions: [HabitUnit] {
        [.count, .minutes, .hours, .steps, .glasses, .calories, .grams, .milligrams, .milliliters, .servings, .flights, .words, .kilograms, .centimeters]
    }

    var displayName: String {
        switch self {
        case .count: "Count"
        case .minutes: "Minutes"
        case .hours: "Hours"
        case .steps: "Steps"
        case .glasses: "Glasses"
        case .calories: "Calories"
        case .grams: "Grams"
        case .milligrams: "Milligrams"
        case .milliliters: "Milliliters"
        case .servings: "Servings"
        case .flights: "Flights"
        case .words: "Words"
        case .kilograms: "Kilograms"
        case .centimeters: "Centimeters"
        case .mmHg: "mmHg"
        case .milligramsPerDeciliter: "mg/dL"
        case .percent: "%"
        }
    }
}
