import XCTest
@testable import Forge

/// Tests the core-prayer template enforcement — the authoritative rules
/// `HabitFormView.buildHabit()` applies via `CorePrayerTemplate.enforce()` for
/// the 12 restricted templates (5 Fard + 5 Sunnah + Witr + Qiyam al-Layl),
/// across the 4 behavior buckets: `binaryComplete`, `witrLike`,
/// `qabliyahDhuhr`, `qiyam`. Plus the odd/even goal clamps and the
/// tap-to-complete arithmetic each bucket's enforced (goal, step) must
/// satisfy.
final class CorePrayerTemplateTests: XCTestCase {

    // MARK: Classification

    func testBucketClassification() {
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-fajr-fard"), .binaryComplete)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-sunnah-after-maghrib"), .binaryComplete)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-witr"), .witrLike)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-sunnah-before-dhuhr"), .qabliyahDhuhr)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-qiyam"), .qiyam)
        // NOT the adhkar-after-prayer templates, and not other habits.
        XCTAssertNil(CorePrayerTemplate.kind(for: "islamic-dhikr-after-fajr"))
        XCTAssertNil(CorePrayerTemplate.kind(for: "islamic-tasbih-subhanallah"))
        XCTAssertNil(CorePrayerTemplate.kind(for: nil))
        XCTAssertEqual(CorePrayerTemplate.allIDs.count, 12)
        XCTAssertEqual(CorePrayerTemplate.binaryCompleteIDs.count, 9)
    }

    /// All 12 ids classify to exactly one of the 4 buckets — no id is
    /// double-counted or missing.
    func testEveryIDClassifiesToExactlyOneBucket() {
        for id in CorePrayerTemplate.allIDs {
            XCTAssertNotNil(CorePrayerTemplate.kind(for: id), "\(id) should classify to a bucket")
        }
        XCTAssertEqual(
            CorePrayerTemplate.binaryCompleteIDs.count + 1 + 1 + 1,
            CorePrayerTemplate.allIDs.count,
            "9 binaryComplete + 1 witrLike + 1 qabliyahDhuhr + 1 qiyam = 12, no overlap"
        )
    }

    // MARK: Odd/even clamps

    func testNearestOddGoalClamping() {
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(4), 5)   // even → next odd (3 or 5 both valid per spec)
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(7), 7)   // odd stays
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(2), 3)
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(1), 1)
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(0), 1)   // below 1 clamps to 1
        XCTAssertTrue(Int(CorePrayerTemplate.nearestOddGoal(6)) % 2 == 1)
    }

    func testNearestEvenGoalClamping() {
        XCTAssertEqual(CorePrayerTemplate.nearestEvenGoal(3), 4)  // odd → next even (2 or 4 both valid per spec)
        XCTAssertEqual(CorePrayerTemplate.nearestEvenGoal(6), 6)  // even stays
        XCTAssertEqual(CorePrayerTemplate.nearestEvenGoal(5), 6)
        XCTAssertEqual(CorePrayerTemplate.nearestEvenGoal(2), 2)
        XCTAssertEqual(CorePrayerTemplate.nearestEvenGoal(0), 2)  // below 2 clamps to 2 (min valid Qiyam)
        XCTAssertEqual(CorePrayerTemplate.nearestEvenGoal(1), 2)
        XCTAssertTrue(Int(CorePrayerTemplate.nearestEvenGoal(7)) % 2 == 0)
    }

    func testNearestQiyamStepSnapsToTwoOrFour() {
        XCTAssertEqual(CorePrayerTemplate.nearestQiyamStep(2), 2)
        XCTAssertEqual(CorePrayerTemplate.nearestQiyamStep(4), 4)
        XCTAssertEqual(CorePrayerTemplate.nearestQiyamStep(1), 2)   // below 3 snaps to 2
        XCTAssertEqual(CorePrayerTemplate.nearestQiyamStep(3), 4)   // 3+ snaps to 4
        XCTAssertEqual(CorePrayerTemplate.nearestQiyamStep(50), 4)  // any garbage value still lands on 2 or 4
    }

    // MARK: enforce() per bucket

    private func habit(templateID: String, goal: Double, step: Double) -> Habit {
        Habit(title: "Tampered Title", category: .good, sourceTemplateID: templateID,
              goal: goal, unit: .minutes, step: step,
              goalProgression: GoalProgression(incrementAmount: 10, intervalDays: 30),
              lastGoalIncreaseDate: .now,
              repeatMode: .specificDays([1, 3]),
              timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 0)))
    }

    /// Every bucket must force the canonical title, daily repeat, no
    /// progression, and preserve the `PrayerAnchor` untouched — verified for
    /// all 12 ids in one sweep (the "title immutability... for all 12" /
    /// "repeatMode forced daily + timeMode preserving PrayerAnchor for all
    /// 12" requirement).
    func testEveryTemplateForcesTitleRepeatProgressionAndPreservesAnchor() {
        for id in CorePrayerTemplate.allIDs {
            let out = CorePrayerTemplate.enforce(habit(templateID: id, goal: 99, step: 50))
            let canonical = TemplateCatalog.template(withID: id)?.title
            XCTAssertNotNil(canonical, "\(id) must exist in TemplateCatalog")
            XCTAssertEqual(out.title, canonical, "\(id): title must be forced to canonical, never the tampered value")
            XCTAssertEqual(out.repeatMode, .daily, "\(id): repeat forced to daily even though input was specificDays")
            XCTAssertNil(out.goalProgression, "\(id): no goal progression for any core prayer")
            XCTAssertNil(out.lastGoalIncreaseDate, "\(id)")
            XCTAssertEqual(out.timeMode, .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 0)),
                           "\(id): PrayerAnchor must survive untouched")
            XCTAssertEqual(out.unit, .count, "\(id): every core prayer bucket forces .count")
        }
    }

    func testEnforceBinaryComplete() {
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-fajr-fard", goal: 5, step: 3))
        XCTAssertEqual(out.title, "Fajr Prayer")
        XCTAssertEqual(out.goal, 1)
        XCTAssertEqual(out.step, 1)
    }

    func testEnforceQabliyahDhuhrIsFullyFixedIgnoringUserInput() {
        // Even a wildly tampered goal/step (99/50) must be forced back to the
        // fixed 4/2 — Goal and Increment are hidden from the form entirely,
        // so nothing about this bucket is user-editable anymore.
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-sunnah-before-dhuhr", goal: 99, step: 50))
        XCTAssertEqual(out.title, "Sunnah before Dhuhr (4 rak'ah)")
        XCTAssertEqual(out.goal, 4)
        XCTAssertEqual(out.step, 2)
    }

    func testEnforceWitrLikeOddClampAndStepMirrorsGoal() {
        // A tampered even goal (4) + unrelated step (7) → odd goal, and step
        // must equal that (clamped) goal exactly — never a fixed 2 anymore.
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-witr", goal: 4, step: 7))
        XCTAssertTrue(Int(out.goal) % 2 == 1, "Witr goal must be odd")
        XCTAssertEqual(out.step, out.goal, "Witr's step must always mirror its (clamped) goal")

        // A legitimately odd input goal is preserved, and step still mirrors it.
        let out7 = CorePrayerTemplate.enforce(habit(templateID: "islamic-witr", goal: 7, step: 2))
        XCTAssertEqual(out7.goal, 7)
        XCTAssertEqual(out7.step, 7)

        // Minimum valid Witr.
        let out1 = CorePrayerTemplate.enforce(habit(templateID: "islamic-witr", goal: 1, step: 1))
        XCTAssertEqual(out1.goal, 1)
        XCTAssertEqual(out1.step, 1)
    }

    func testEnforceQiyamEvenClampAndStepSnapsToTwoOrFour() {
        // Odd goal (3) + a step that isn't 2 or 4 (7) → even goal, step
        // snapped to the nearest of {2, 4}.
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-qiyam", goal: 3, step: 7))
        XCTAssertTrue(Int(out.goal) % 2 == 0, "Qiyam goal must be even")
        XCTAssertTrue(out.step == 2 || out.step == 4, "Qiyam step must be exactly 2 or 4")

        // Legitimate values pass through unchanged.
        let out4 = CorePrayerTemplate.enforce(habit(templateID: "islamic-qiyam", goal: 4, step: 4))
        XCTAssertEqual(out4.goal, 4)
        XCTAssertEqual(out4.step, 4)
    }

    func testEnforceIsNoOpForNonCorePrayer() {
        let raw = Habit(title: "Read", category: .good, sourceTemplateID: "islamic-read-quran",
                        goal: 15, unit: .minutes, step: 5, repeatMode: .daily)
        let out = CorePrayerTemplate.enforce(raw)
        XCTAssertEqual(out, raw, "adhkar/quran/other templates are untouched")

        // Also confirmed for the 5 "Adhkar after <prayer>" templates
        // specifically — deliberately NOT part of the 12 restricted ones,
        // even though they share the same .prayerRelative TimeMode.
        let adhkar = Habit(title: "My Own Title", category: .good, sourceTemplateID: "islamic-dhikr-after-fajr",
                           goal: 3, unit: .count, step: 1, repeatMode: .timesPerWeek(4),
                           timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 5)))
        let adhkarOut = CorePrayerTemplate.enforce(adhkar)
        XCTAssertEqual(adhkarOut, adhkar, "adhkar-after-prayer templates stay fully editable/unrestricted")
    }

    // MARK: Singleton derivation (all 4 buckets)

    func testAddedSingletonIDsCoversAllFourBucketsAndExcludesArchivedAndNonCore() {
        let fajr = Habit(title: "Fajr Prayer", category: .good, sourceTemplateID: "islamic-fajr-fard")
        let witr = Habit(title: "Witr Prayer", category: .good, sourceTemplateID: "islamic-witr")
        let qabliyah = Habit(title: "Sunnah before Dhuhr (4 rak'ah)", category: .good, sourceTemplateID: "islamic-sunnah-before-dhuhr")
        let qiyam = Habit(title: "Qiyam al-Layl", category: .good, sourceTemplateID: "islamic-qiyam")
        var archivedDhuhr = Habit(title: "Dhuhr Prayer", category: .good, sourceTemplateID: "islamic-dhuhr-fard")
        archivedDhuhr.isArchived = true
        let dhikr = Habit(title: "SubhanAllah", category: .good, sourceTemplateID: "islamic-tasbih-subhanallah")
        let custom = Habit(title: "Custom", category: .good, sourceTemplateID: nil)

        let ids = CorePrayerTemplate.addedSingletonIDs(from: [fajr, witr, qabliyah, qiyam, archivedDhuhr, dhikr, custom])
        XCTAssertEqual(ids, ["islamic-fajr-fard", "islamic-witr", "islamic-sunnah-before-dhuhr", "islamic-qiyam"],
                       "one non-archived habit per bucket all occupy their singleton slots; archived/non-core do not")
    }

    // MARK: Tap-to-complete arithmetic (mirrors HomeView.handleTap's real
    // `count = min(count + step, goal)`, complete once `count >= goal`
    // formula exactly — verified against the enforced (goal, step) pairs
    // each bucket actually produces).

    /// Number of taps needed to complete a quantity habit with the given
    /// (goal, step) — a direct mirror of `HomeView.handleTap`'s real
    /// increment formula, not a guess.
    private func tapsToComplete(goal: Double, step: Double) -> Int {
        var count = 0.0
        var taps = 0
        while count < goal && taps < 1000 {
            count = min(count + step, goal)
            taps += 1
        }
        return taps
    }

    func testBinaryCompleteTapsToCompleteInOneTap() {
        let q = CorePrayerTemplate.enforcedQuantity(kind: .binaryComplete, userGoal: 1, userStep: 1)
        XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 1)
    }

    func testWitrLikeCompletesInOneTapAtVariousGoals() {
        for rawGoal in [1.0, 2.0, 3.0, 4.0, 5.0, 7.0, 9.0] {
            let q = CorePrayerTemplate.enforcedQuantity(kind: .witrLike, userGoal: rawGoal, userStep: 999)
            XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 1,
                           "Witr with raw goal \(rawGoal) (enforced goal \(q.goal)) must complete in exactly 1 tap")
        }
    }

    func testQabliyahDhuhrCompletesInExactlyTwoTaps() {
        let q = CorePrayerTemplate.enforcedQuantity(kind: .qabliyahDhuhr, userGoal: 1, userStep: 1)
        XCTAssertEqual(q.goal, 4)
        XCTAssertEqual(q.step, 2)
        XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 2)
    }

    func testQiyamTapsToCompleteMatchChosenIncrement() {
        // goal 2 / step 2 → 1 tap.
        var q = CorePrayerTemplate.enforcedQuantity(kind: .qiyam, userGoal: 2, userStep: 2)
        XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 1)

        // goal 4 / step 2 → 2 taps.
        q = CorePrayerTemplate.enforcedQuantity(kind: .qiyam, userGoal: 4, userStep: 2)
        XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 2)

        // goal 2 / step 4 → clamped by min(), still 1 tap.
        q = CorePrayerTemplate.enforcedQuantity(kind: .qiyam, userGoal: 2, userStep: 4)
        XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 1)

        // goal 6 / step 4 → 2 taps (4, then 6).
        q = CorePrayerTemplate.enforcedQuantity(kind: .qiyam, userGoal: 6, userStep: 4)
        XCTAssertEqual(tapsToComplete(goal: q.goal, step: q.step), 2)
    }
}
