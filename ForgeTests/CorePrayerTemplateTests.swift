import XCTest
@testable import Forge

/// Tests the core-prayer template enforcement — the authoritative rules
/// `HabitFormView.buildHabit()` applies via `CorePrayerTemplate.enforce()` for
/// the 11 restricted templates (5 Fard + 5 Sunnah + Witr), plus the Witr
/// odd-clamp and the singleton "already added" derivation.
final class CorePrayerTemplateTests: XCTestCase {

    // MARK: Classification

    func testBucketClassification() {
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-fajr-fard"), .binary)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-sunnah-after-maghrib"), .binary)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-sunnah-before-dhuhr"), .qabliyahDhuhrSunnah)
        XCTAssertEqual(CorePrayerTemplate.kind(for: "islamic-witr"), .witr)
        // NOT the adhkar-after-prayer templates, and not other habits.
        XCTAssertNil(CorePrayerTemplate.kind(for: "islamic-dhikr-after-fajr"))
        XCTAssertNil(CorePrayerTemplate.kind(for: "islamic-tasbih-subhanallah"))
        XCTAssertNil(CorePrayerTemplate.kind(for: nil))
        XCTAssertEqual(CorePrayerTemplate.allIDs.count, 11)
    }

    // MARK: Witr odd-clamp

    func testNearestOddGoalClamping() {
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(4), 5)   // even → next odd (3 or 5 both valid per spec)
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(7), 7)   // odd stays
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(2), 3)
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(1), 1)
        XCTAssertEqual(CorePrayerTemplate.nearestOddGoal(0), 1)   // below 1 clamps to 1
        XCTAssertTrue(Int(CorePrayerTemplate.nearestOddGoal(6)) % 2 == 1)
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

    func testEnforceBinary() {
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-fajr-fard", goal: 5, step: 3))
        XCTAssertEqual(out.title, "Fajr Prayer", "title forced to canonical, never the tampered value")
        XCTAssertEqual(out.goal, 1)
        XCTAssertEqual(out.step, 1)
        XCTAssertEqual(out.unit, .count)
        XCTAssertEqual(out.repeatMode, .daily, "repeat forced to daily even though input was specificDays")
        XCTAssertNil(out.goalProgression)
        XCTAssertNil(out.lastGoalIncreaseDate)
        // PrayerAnchor preserved untouched.
        XCTAssertEqual(out.timeMode, .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 0)))
    }

    func testEnforceQabliyahDhuhrKeepsUserQuantity() {
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-sunnah-before-dhuhr", goal: 4, step: 2))
        XCTAssertEqual(out.title, "Sunnah before Dhuhr (4 rak'ah)")
        XCTAssertEqual(out.goal, 4, "user goal kept (editable quantity)")
        XCTAssertEqual(out.step, 2, "user step kept")
        XCTAssertEqual(out.unit, .count)
        XCTAssertEqual(out.repeatMode, .daily)
        XCTAssertNil(out.goalProgression)
        XCTAssertEqual(out.timeMode, .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 0)))
    }

    func testEnforceWitrOddClampAndFixedStep() {
        // A tampered even goal + wrong step → odd goal, step forced to 2.
        let out = CorePrayerTemplate.enforce(habit(templateID: "islamic-witr", goal: 4, step: 7))
        XCTAssertEqual(out.title, "Witr Prayer")
        XCTAssertTrue(Int(out.goal) % 2 == 1, "Witr goal must be odd")
        XCTAssertEqual(out.step, 2, "Witr step is fixed at 2")
        XCTAssertEqual(out.unit, .count)
        XCTAssertEqual(out.repeatMode, .daily)
        // An odd input goal is preserved.
        let out7 = CorePrayerTemplate.enforce(habit(templateID: "islamic-witr", goal: 7, step: 2))
        XCTAssertEqual(out7.goal, 7)
    }

    func testEnforceIsNoOpForNonCorePrayer() {
        let raw = Habit(title: "Read", category: .good, sourceTemplateID: "islamic-read-quran",
                        goal: 15, unit: .minutes, step: 5, repeatMode: .daily)
        let out = CorePrayerTemplate.enforce(raw)
        XCTAssertEqual(out, raw, "adhkar/quran/other templates are untouched")
    }

    // MARK: Singleton derivation

    func testAddedSingletonIDsExcludesArchivedAndNonCore() {
        let fajr = Habit(title: "Fajr Prayer", category: .good, sourceTemplateID: "islamic-fajr-fard")
        var archivedDhuhr = Habit(title: "Dhuhr Prayer", category: .good, sourceTemplateID: "islamic-dhuhr-fard")
        archivedDhuhr.isArchived = true
        let dhikr = Habit(title: "SubhanAllah", category: .good, sourceTemplateID: "islamic-tasbih-subhanallah")
        let custom = Habit(title: "Custom", category: .good, sourceTemplateID: nil)

        let ids = CorePrayerTemplate.addedSingletonIDs(from: [fajr, archivedDhuhr, dhikr, custom])
        XCTAssertEqual(ids, ["islamic-fajr-fard"],
                       "only the non-archived core-prayer habit occupies a singleton slot")
    }
}
