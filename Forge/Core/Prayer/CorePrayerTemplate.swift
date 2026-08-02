import Foundation

/// The four behavior buckets for the 12 core prayer templates (5 Fard +
/// 5 Sunnah + Witr + Qiyam al-Layl) in the Islamic pack's "Prayers" section.
/// The 5 "Adhkar after &lt;prayer&gt;" templates in the same section are
/// deliberately **not** here — they stay fully editable/unrestricted.
///
/// **Supersedes an earlier 3-bucket/11-template design** (`.binary`,
/// `.qabliyahDhuhrSunnah`, `.witr`) from the same investigation — that design
/// was never shipped as final; this is the confirmed spec.
enum CorePrayerTemplateKind: Equatable, Sendable, CaseIterable {
    /// Binary "done / not done" prayer — fixed goal 1, count, step 1; no goal
    /// UI at all. (5 Fard + the 4 plain Sunnah.) A single tap completes it,
    /// same as any other binary habit in the app.
    case binaryComplete
    /// Witr — an editable, **odd**-clamped goal with no Increment field at
    /// all: `step` always mirrors the (clamped) goal internally, so a single
    /// tap completes it fully regardless of the configured goal.
    case witrLike
    /// Qabliyah Dhuhr — genuinely two sets of 2 rak'ah, but now fully fixed
    /// under the hood (goal 4 / step 2) with **both** Goal and Increment
    /// hidden from the form, same as `binaryComplete`. Two taps complete it.
    case qabliyahDhuhr
    /// Qiyam al-Layl (new) — an editable, **even**-clamped goal, with a
    /// constrained Increment of *only* 2 or 4 (a segmented picker, never a
    /// free Stepper/TextField).
    case qiyam
}

/// Single source of truth for which of the 12 core prayer templates a
/// `sourceTemplateID` is, and the enforcement that applies to them.
/// `HabitFormView` and `CategoryDetailView` both consult this rather than
/// duplicating the id list.
enum CorePrayerTemplate {
    /// Binary group: 5 Fard + 4 plain Sunnah (Qabliyah Dhuhr, Witr, and Qiyam
    /// are the three quantity exceptions, handled separately).
    static let binaryCompleteIDs: Set<String> = [
        "islamic-fajr-fard", "islamic-dhuhr-fard", "islamic-asr-fard",
        "islamic-maghrib-fard", "islamic-isha-fard",
        "islamic-sunnah-before-fajr", "islamic-sunnah-after-dhuhr",
        "islamic-sunnah-after-maghrib", "islamic-sunnah-after-isha",
    ]
    static let witrID = "islamic-witr"
    static let qabliyahDhuhrID = "islamic-sunnah-before-dhuhr"
    static let qiyamID = "islamic-qiyam"

    /// All 12 restricted-behavior template ids.
    static var allIDs: Set<String> { binaryCompleteIDs.union([witrID, qabliyahDhuhrID, qiyamID]) }

    static func kind(for sourceTemplateID: String?) -> CorePrayerTemplateKind? {
        guard let id = sourceTemplateID else { return nil }
        if binaryCompleteIDs.contains(id) { return .binaryComplete }
        if id == witrID { return .witrLike }
        if id == qabliyahDhuhrID { return .qabliyahDhuhr }
        if id == qiyamID { return .qiyam }
        return nil
    }

    static func isCorePrayerTemplate(_ sourceTemplateID: String?) -> Bool {
        kind(for: sourceTemplateID) != nil
    }

    /// Snap a goal to the nearest valid **odd** integer (>= 1) for Witr —
    /// even values round up to the next odd (4 → 5, 6 → 7), odd values stay
    /// put, and anything below 1 clamps to 1.
    static func nearestOddGoal(_ value: Double) -> Double {
        let n = max(1, Int(value.rounded()))
        return Double(n % 2 == 1 ? n : n + 1)
    }

    /// Snap a goal to the nearest valid **even** integer (>= 2) for Qiyam —
    /// odd values round up to the next even (3 → 4, 5 → 6), even values stay
    /// put, and anything below 2 clamps to 2 (the minimum valid Qiyam goal).
    static func nearestEvenGoal(_ value: Double) -> Double {
        let n = max(2, Int(value.rounded()))
        return Double(n % 2 == 0 ? n : n + 1)
    }

    /// Snap an increment to the nearest of Qiyam's two valid values, {2, 4}
    /// — the segmented-picker constraint enforced defensively here too, so
    /// `enforce()` stays authoritative even against a value that never went
    /// through the picker (a tampered or pre-existing habit).
    static func nearestQiyamStep(_ value: Double) -> Double {
        value >= 3 ? 4 : 2
    }

    /// The enforced (goal, step, unit) for a bucket given the user-entered
    /// goal/step (ignored entirely for the two fully-fixed buckets).
    static func enforcedQuantity(kind: CorePrayerTemplateKind, userGoal: Double, userStep: Double) -> (goal: Double, step: Double, unit: HabitUnit) {
        switch kind {
        case .binaryComplete:
            return (1, 1, .count)
        case .qabliyahDhuhr:
            // Fully fixed — Goal and Increment are hidden from the form
            // entirely, so the user's raw values are never trusted here.
            return (4, 2, .count)
        case .witrLike:
            // No Increment field at all — step always mirrors the
            // (odd-clamped) goal, so a single tap completes it regardless of
            // the configured goal.
            let goal = nearestOddGoal(userGoal)
            return (goal, goal, .count)
        case .qiyam:
            return (nearestEvenGoal(userGoal), nearestQiyamStep(userStep), .count)
        }
    }

    /// Applies **all** core-prayer enforcement to a habit built from the
    /// form's raw state — the authoritative rules `HabitFormView.buildHabit`
    /// runs, factored out so it's unit-testable directly:
    /// - title forced to the canonical template title (never renameable),
    /// - `repeatMode` forced to `.daily`,
    /// - no goal progression,
    /// - bucket-specific goal/step/unit,
    /// - `timeMode` left untouched (the `PrayerAnchor` is already preserved by
    ///   `buildHabit`'s existing `preservedPrayerAnchor` path).
    /// Returns the habit unchanged when it isn't one of the 12.
    static func enforce(_ habit: Habit) -> Habit {
        guard let kind = kind(for: habit.sourceTemplateID) else { return habit }
        var h = habit
        if let id = habit.sourceTemplateID, let canonical = TemplateCatalog.template(withID: id)?.title {
            h.title = canonical
        }
        h.repeatMode = .daily
        h.goalProgression = nil
        h.lastGoalIncreaseDate = nil
        let q = enforcedQuantity(kind: kind, userGoal: habit.goal, userStep: habit.step)
        h.goal = q.goal
        h.step = q.step
        h.unit = q.unit
        return h
    }

    /// The subset of `habits` that already occupy a core-prayer singleton slot
    /// — a non-archived habit whose `sourceTemplateID` is one of the 12. Their
    /// templates must render as "Added" (non-addable) in `CategoryDetailView`.
    /// Archiving/deleting frees the slot (so this only counts non-archived).
    static func addedSingletonIDs(from habits: [Habit]) -> Set<String> {
        Set(habits.lazy
            .filter { !$0.isArchived }
            .compactMap { $0.sourceTemplateID }
            .filter { isCorePrayerTemplate($0) })
    }
}
