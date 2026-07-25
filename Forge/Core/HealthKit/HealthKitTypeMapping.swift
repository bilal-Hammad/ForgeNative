import Foundation
import HealthKit

/// Maps a `HabitTemplate.id` (carried onto the created `Habit` as
/// `sourceTemplateID`) to the real HealthKit type it should read/write.
///
/// **Two real data problems this surfaced, since fixed at the source in
/// `TemplateCatalog` rather than papered over here:**
/// 1. `"cold-shower"` and `"vitamins"` used to be tagged `isHealthKitTracked`,
///    but neither has an actual corresponding HealthKit type — HealthKit has
///    no "cold shower taken" concept at all, and its vitamin types are
///    per-specific-vitamin-with-dose (e.g. vitamin C in mg), not a fit for a
///    generic "took vitamins" habit. Both are now plain manual habits in
///    `TemplateCatalog` (no `isHealthKitTracked`, no badge) and were never
///    added to `byTemplateID` below — `HealthKitService` treats "no mapping
///    found" as "not really HealthKit-backed," so this is also the fallback
///    path for any future template with the same mismatch.
/// 2. `"hk-alcohol"` ("Limit Alcoholic Drinks") used to be stored with
///    `unit: .grams, goal: 14` — but HealthKit has no "grams of pure
///    alcohol" quantity type, only `numberOfAlcoholicBeverages` (a plain
///    drink *count*). `TemplateCatalog` now stores it as `unit: .count,
///    goal: 2` (matching common daily moderate-drinking guidance), so the
///    mapping below against `numberOfAlcoholicBeverages` is an exact unit
///    match rather than an approximation.
///
/// **Three more real HealthKit types with zero templates exist as of this
/// pass and were investigated but intentionally not mapped — no real
/// HealthKit type exists for them, confirmed against the actual installed
/// SDK's `HKTypeIdentifiers.h` (not guessed from memory):**
/// - **Flossing** ("Floss Teeth") — HealthKit has `toothbrushingEvent`
///   (iOS 13+) but nothing for flossing specifically. Mapping this to
///   toothbrushing would auto-complete a flossing habit because the user
///   brushed their teeth, which is simply false data — worse than no
///   mapping at all. Stays a plain manual habit, same treatment as
///   cold-shower/vitamins above.
/// - **"Pelvic floor" exercises** — the only pelvic-related type is
///   `HKCategoryTypeIdentifierPelvicPain` (a symptom-severity log), which
///   means something categorically different from an exercise habit. No
///   real type exists for pelvic-floor exercise tracking.
/// - **"Sleep diary"** — no distinct type beyond `sleepAnalysis` (already
///   mapped via `"sleep"` below). `sleepChanges`/`sleepApneaEvent` exist but
///   are Watch-detected signals, not something a "sleep diary" habit could
///   mean. Treated as the same real type as the existing `"sleep"` template
///   rather than inventing a second, redundant mapping.
///
/// **Read-only vitals/reproductive-health types (blood pressure, body
/// measurements, menstrual/contraceptive logging) intentionally never
/// support write-back**, for two different reasons documented per-mapping
/// below: Forge's completion UI has no numeric-value entry for a real vital
/// reading (a quantity habit's "step" is a fixed per-tap increment, not a
/// place to type "72kg" or "120/80mmHg" — writing a fabricated value back
/// to Health would be actively harmful data), and reproductive-health
/// entries (menstrual flow, contraceptive method) are sensitive enough that
/// read-only is the conservative default regardless, matching how the
/// existing Bad-category "moderation" habits already stay closer to
/// read/observe than to Forge originating new Health records.
///
/// **Blood Pressure reads `.bloodPressureSystolic` directly, not
/// `HKCorrelationType(.bloodPressure)` — a real crash found empirically
/// this pass, not a design preference.** `Kind` has no `.correlation` case
/// at all for exactly this reason: HealthKit flatly disallows requesting
/// *any* authorization — share **or** read — on a correlation type
/// directly (confirmed live: `HKHealthStore.requestAuthorization` threw
/// `NSInvalidArgumentException: Authorization to read the following types
/// is disallowed: HKCorrelationTypeIdentifierBloodPressure` when tried).
/// Apple's model is that you authorize/query a correlation's *constituent*
/// quantity types instead — the correlation object itself is just a
/// container built from those. Since this app only ever needs "was a
/// reading logged today" (see `CompletionRule.discreteCount`), reading
/// `.bloodPressureSystolic` presence alone is sufficient and exact: any
/// real blood pressure entry, correlation-composed or not, includes a
/// systolic sample.
enum HealthKitTypeMapping {
    enum Kind {
        case quantity(HKQuantityTypeIdentifier)
        case category(HKCategoryTypeIdentifier)
        case workout(HKWorkoutActivityType)
    }

    /// How a habit's real-world completion is judged against `habit.goal`.
    enum CompletionRule {
        /// Sum of values in range must reach/exceed `goal` — the default
        /// for additive habits (water, steps, workout minutes).
        case cumulativeMinimum
        /// Sum of values in range must stay at/under `goal` — §8's Bad-
        /// category "moderation" habits (mirrors how `Completion.isComplete`
        /// already means "avoided," not "reached," for a Bad habit).
        case cumulativeLimit
        /// Count of *discrete samples* logged in range must reach/exceed
        /// `goal` — not a sum of magnitudes, a count of events. Fits two
        /// different real shapes: "log this once a day" (goal 1 — blood
        /// pressure, weight, a menstrual/contraceptive entry) and "this
        /// happens several times a day" (goal >1 — handwashing).
        case discreteCount
    }

    struct Mapping {
        let kind: Kind
        /// Unit samples are read/written in. Unused (but harmless) for
        /// `.discreteCount` types, which only ever count samples.
        let hkUnit: HKUnit
        /// Multiply a value in `hkUnit` by this to get the habit's own
        /// `HabitUnit` value (e.g. glasses per US fluid ounce).
        let habitUnitsPerHKUnit: Double
        let rule: CompletionRule
        /// Whether a manual tap/long-press in Forge writes back to Health at
        /// all — independent of read/authorization status. `false` for
        /// every read-only vitals/reproductive-health type (see this type's
        /// doc comment for why); `true` for everything Forge's own
        /// completion UI can honestly represent (a plain toggle, a fixed
        /// per-tap increment, or a workout duration).
        let supportsWriteBack: Bool
        /// Restricts a `.category` read to samples with this specific
        /// `HKCategoryValue` raw value, instead of counting every sample of
        /// the type — used only by `"hk-contraceptive-pill"`, so logging an
        /// IUD/patch/injection elsewhere in Health doesn't also complete a
        /// habit specifically about the oral pill.
        let categoryValueFilter: Int?

        init(
            kind: Kind,
            hkUnit: HKUnit,
            habitUnitsPerHKUnit: Double = 1,
            rule: CompletionRule,
            supportsWriteBack: Bool,
            categoryValueFilter: Int? = nil
        ) {
            self.kind = kind
            self.hkUnit = hkUnit
            self.habitUnitsPerHKUnit = habitUnitsPerHKUnit
            self.rule = rule
            self.supportsWriteBack = supportsWriteBack
            self.categoryValueFilter = categoryValueFilter
        }

        /// Every `Kind` case maps to a real `HKSampleType` subclass, so this
        /// is typed concretely rather than the broader `HKObjectType` —
        /// callers need `HKSampleType` for authorization/query/save calls
        /// without an extra cast.
        var sampleType: HKSampleType {
            switch kind {
            case .quantity(let identifier): HKQuantityType(identifier)
            case .category(let identifier): HKCategoryType(identifier)
            case .workout: HKWorkoutType.workoutType()
            }
        }
    }

    /// One US "glass" of water, by the common 8-glasses-a-day convention.
    private static let fluidOuncesPerGlass = 8.0

    static let byTemplateID: [String: Mapping] = [
        // MARK: Existing — cumulative, workout/quantity/category

        "drink-water": Mapping(kind: .quantity(.dietaryWater), hkUnit: .fluidOunceUS(), habitUnitsPerHKUnit: 1 / fluidOuncesPerGlass, rule: .cumulativeMinimum, supportsWriteBack: true),
        "run": Mapping(kind: .workout(.running), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "cycling": Mapping(kind: .workout(.cycling), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "swim": Mapping(kind: .workout(.swimming), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "yoga": Mapping(kind: .workout(.yoga), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "workout": Mapping(kind: .workout(.traditionalStrengthTraining), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "steps-10k": Mapping(kind: .quantity(.stepCount), hkUnit: .count(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "sleep": Mapping(kind: .category(.sleepAnalysis), hkUnit: .hour(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "hk-mindful": Mapping(kind: .category(.mindfulSession), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        "hk-coffee": Mapping(kind: .quantity(.dietaryCaffeine), hkUnit: .gramUnit(with: .milli), rule: .cumulativeLimit, supportsWriteBack: true),
        "hk-alcohol": Mapping(kind: .quantity(.numberOfAlcoholicBeverages), hkUnit: .count(), rule: .cumulativeLimit, supportsWriteBack: true),

        // MARK: New this pass — more workouts, same cumulative-minutes shape

        "hk-basketball": Mapping(kind: .workout(.basketball), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),
        // No literal "Aerobics" HKWorkoutActivityType exists (verified
        // against the installed SDK's HKWorkout.h) — `.mixedCardio`
        // (Apple's own successor to the older, now-deprecated
        // "Mixed Metabolic Cardio Training") is the closest real match for
        // a generic aerobic-training habit. Flagged as an interpretation,
        // not an exact-name match, the way every other mapping in this file
        // is.
        "hk-aerobic": Mapping(kind: .workout(.mixedCardio), hkUnit: .minute(), rule: .cumulativeMinimum, supportsWriteBack: true),

        // MARK: New this pass — discrete-count, write-back true
        // (Forge's completion UI can honestly represent these: a plain
        // "did this happen" toggle, or counting up to a daily frequency.)

        "hk-handwashing": Mapping(kind: .category(.handwashingEvent), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: true),

        // MARK: New this pass — discrete-count, read-only
        // (no honest value for Forge's UI to write back — see type doc.)

        // See the type's doc comment — reads `.bloodPressureSystolic`
        // directly, not the `.bloodPressure` correlation type, which
        // HealthKit disallows requesting any authorization on at all.
        "hk-blood-pressure": Mapping(kind: .quantity(.bloodPressureSystolic), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),
        "hk-weight": Mapping(kind: .quantity(.bodyMass), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),
        "hk-lean-mass": Mapping(kind: .quantity(.leanBodyMass), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),
        "hk-body-fat": Mapping(kind: .quantity(.bodyFatPercentage), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),
        "hk-height": Mapping(kind: .quantity(.height), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),
        "hk-blood-glucose": Mapping(kind: .quantity(.bloodGlucose), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),

        // MARK: New this pass — discrete-count, read-only, sensitive data
        // (reproductive health — conservative read-only default regardless
        // of whether Forge's UI *could* write a value; see type doc.)

        "hk-menstrual": Mapping(kind: .category(.menstrualFlow), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false),
        // Filtered to `.oral` specifically — `contraceptive` covers every
        // method (implant/injection/IUD/ring/patch/oral); without this
        // filter, logging e.g. a patch change in Health would incorrectly
        // complete a habit titled "Contraceptive Pill."
        "hk-contraceptive-pill": Mapping(kind: .category(.contraceptive), hkUnit: .count(), rule: .discreteCount, supportsWriteBack: false, categoryValueFilter: HKCategoryValueContraceptive.oral.rawValue),
    ]

    static func mapping(for habit: Habit) -> Mapping? {
        guard habit.isHealthKitTracked, let templateID = habit.sourceTemplateID else { return nil }
        return byTemplateID[templateID]
    }

    /// Every distinct HealthKit sample type actually in use across the
    /// mappings above — the set `HealthKitService` requests authorization
    /// for and registers background observers on. Deduplicated since
    /// several templates (run/cycling/swim/yoga/workout/basketball/aerobic)
    /// all share the one underlying `HKWorkoutType`.
    static var allSampleTypes: Set<HKSampleType> {
        Set(byTemplateID.values.map(\.sampleType))
    }
}
