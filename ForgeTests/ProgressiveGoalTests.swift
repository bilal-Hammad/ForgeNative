import XCTest
@testable import Forge

/// P1 Phase 5 — the non-retroactive guarantee for progressive/changing goals:
/// a past day's count-vs-goal ratio is measured against the goal that was in
/// effect *that* day (`Completion.goalAtCompletion`), never today's.
final class ProgressiveGoalTests: XCTestCase {

    func testEffectiveGoalUsesSnapshotWhenPresent() {
        let c = Completion(habitID: UUID(), date: .now, count: 30, isComplete: true, goalAtCompletion: 30)
        // Even though the habit's goal later grew to 40, this day's goal is 30.
        XCTAssertEqual(c.effectiveGoal(currentGoal: 40), 30)
    }

    func testEffectiveGoalFallsBackToCurrentGoalForLegacyRows() {
        // A completion logged before the snapshot existed (nil) uses the
        // habit's current goal as the best available denominator.
        let c = Completion(habitID: UUID(), date: .now, count: 15, goalAtCompletion: nil)
        XCTAssertEqual(c.effectiveGoal(currentGoal: 20), 20)
    }

    func testGoalIncreaseDoesNotRetroactivelyDemoteACompletedDay() {
        // The day was completed at goal 30 (count 30 == goal 30 → ratio 1.0).
        let day = Completion(habitID: UUID(), date: .now, count: 30, isComplete: true, goalAtCompletion: 30)
        // After the goal auto-increases to 40, the ratio must still read as
        // fully complete for that past day — NOT 30/40 = 0.75.
        let ratio = min(1.0, day.count / day.effectiveGoal(currentGoal: 40))
        XCTAssertEqual(ratio, 1.0, accuracy: 0.0001)
        // The bug this guards against would produce 0.75.
        let buggyRatio = min(1.0, day.count / 40)
        XCTAssertEqual(buggyRatio, 0.75, accuracy: 0.0001)
    }
}
