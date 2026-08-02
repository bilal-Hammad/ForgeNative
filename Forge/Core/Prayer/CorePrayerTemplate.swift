import Foundation

/// The three behavior buckets for the 11 core prayer templates (5 Fard +
/// 5 Sunnah + Witr) in the Islamic pack's "Prayers" section. The 5
/// "Adhkar after <prayer>" templates in the same section are deliberately
/// **not** here — they stay fully editable/unrestricted.
enum CorePrayerTemplateKind: Equatable, Sendable {
    /// Binary "done / not done" prayer — fixed goal 1, count, step 1; no goal
    /// UI. (5 Fard + the 4 plain Sunnah.)
    case binary
    /// Qabliyah Dhuhr sunnah — an editable quantity (two sets of 2 rak'ah), so
    /// a single tap never completes it. Seed goal 4 / step 2.
    case qabliyahDhuhrSunnah
    /// Witr — an editable quantity constrained to an **odd** goal, with the
    /// increment locked at 2 so odd parity is preserved by construction. Seed
    /// goal 1 / step 2.
    case witr
}

/// Single source of truth for which of the 11 core prayer templates a
/// `sourceTemplateID` is, and the enforcement that applies to them.
/// `HabitFormView` and `CategoryDetailView` both consult this rather than
/// duplicating the id list.
enum CorePrayerTemplate {
    /// Binary group: 5 Fard + 4 plain Sunnah (Qabliyah Dhuhr and Witr are the
    /// two quantity exceptions, handled separately).
    static let binaryIDs: Set<String> = [
        "islamic-fajr-fard", "islamic-dhuhr-fard", "islamic-asr-fard",
        "islamic-maghrib-fard", "islamic-isha-fard",
        "islamic-sunnah-before-fajr", "islamic-sunnah-after-dhuhr",
        "islamic-sunnah-after-maghrib", "islamic-sunnah-after-isha",
    ]
    static let qabliyahDhuhrID = "islamic-sunnah-before-dhuhr"
    static let witrID = "islamic-witr"

    /// All 11 restricted-behavior template ids.
    static var allIDs: Set<String> { binaryIDs.union([qabliyahDhuhrID, witrID]) }

    static func kind(for sourceTemplateID: String?) -> CorePrayerTemplateKind? {
        guard let id = sourceTemplateID else { return nil }
        if binaryIDs.contains(id) { return .binary }
        if id == qabliyahDhuhrID { return .qabliyahDhuhrSunnah }
        if id == witrID { return .witr }
        return nil
    }

    static func isCorePrayerTemplate(_ sourceTemplateID: String?) -> Bool {
        kind(for: sourceTemplateID) != nil
    }

    /// Snap a goal to a valid **odd** integer (>= 1) for Witr — even values
    /// round up to the next odd (4 → 5, 6 → 7), odd values stay put, and
    /// anything below 1 clamps to 1.
    static func nearestOddGoal(_ value: Double) -> Double {
        let n = max(1, Int(value.rounded()))
        return Double(n % 2 == 1 ? n : n + 1)
    }

    /// The enforced (goal, step, unit) for a bucket given the user-entered
    /// goal/step. Binary is fixed; the two quantity exceptions keep the user's
    /// goal (Witr odd-clamped) with a fixed unit/step where required.
    static func enforcedQuantity(kind: CorePrayerTemplateKind, userGoal: Double, userStep: Double) -> (goal: Double, step: Double, unit: HabitUnit) {
        switch kind {
        case .binary: return (1, 1, .count)
        case .qabliyahDhuhrSunnah: return (max(1, userGoal), max(1, userStep), .count)
        case .witr: return (nearestOddGoal(userGoal), 2, .count)
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
    /// Returns the habit unchanged when it isn't one of the 11.
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
    /// — a non-archived habit whose `sourceTemplateID` is one of the 11. Their
    /// templates must render as "Added" (non-addable) in `CategoryDetailView`.
    /// Archiving/deleting frees the slot (so this only counts non-archived).
    static func addedSingletonIDs(from habits: [Habit]) -> Set<String> {
        Set(habits.lazy
            .filter { !$0.isArchived }
            .compactMap { $0.sourceTemplateID }
            .filter { isCorePrayerTemplate($0) })
    }
}
