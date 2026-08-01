import XCTest
@testable import Forge

/// P1 Phase 5b — automatic goal-increase engine: bumps at the interval,
/// never retroactively, initializes its anchor without a retroactive bump,
/// and is bounded.
final class GoalProgressionEngineTests: XCTestCase {

    private let calendar = Calendar.current

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: Date()))!
    }

    private func engine(_ repo: InMemoryHabitRepository, maxBumps: Int = 120) -> GoalProgressionEngine {
        GoalProgressionEngine(habitRepository: repo, calendar: calendar, maxBumpsPerRun: maxBumps)
    }

    func testBumpsGoalOncePerElapsedInterval() async throws {
        let repo = InMemoryHabitRepository()
        var habit = Habit(title: "Pushups", category: .good, goal: 20,
                          goalProgression: GoalProgression(incrementAmount: 10, intervalDays: 30))
        // Anchored 65 days ago → two full 30-day intervals elapsed.
        habit.lastGoalIncreaseDate = daysAgo(65)
        try await repo.save(habit)

        await engine(repo).runCatchUp()

        let updated = try await repo.fetch(id: habit.id)!
        XCTAssertEqual(updated.goal, 40, "20 + 2 x 10")
        // Anchor advanced by exactly 2 intervals (60 days), not to now — so the
        // 5 days of partial progress toward the next interval are preserved.
        XCTAssertEqual(calendar.startOfDay(for: updated.lastGoalIncreaseDate!), daysAgo(5))
    }

    func testNoBumpBeforeIntervalElapses() async throws {
        let repo = InMemoryHabitRepository()
        var habit = Habit(title: "Pushups", category: .good, goal: 20,
                          goalProgression: GoalProgression(incrementAmount: 10, intervalDays: 30))
        habit.lastGoalIncreaseDate = daysAgo(10) // < 30
        try await repo.save(habit)

        await engine(repo).runCatchUp()

        let goal = try await repo.fetch(id: habit.id)!.goal
        XCTAssertEqual(goal, 20, "no bump before the interval elapses")
    }

    func testInitializesMissingAnchorWithoutRetroactiveBump() async throws {
        let repo = InMemoryHabitRepository()
        // Progression on, but no anchor set, and a startDate far in the past.
        var habit = Habit(title: "Pushups", category: .good, goal: 20,
                          goalProgression: GoalProgression(incrementAmount: 10, intervalDays: 30),
                          startDate: daysAgo(365))
        habit.lastGoalIncreaseDate = nil
        try await repo.save(habit)

        await engine(repo).runCatchUp()

        let updated = try await repo.fetch(id: habit.id)!
        XCTAssertEqual(updated.goal, 20, "enabling progression must not retroactively bump a year of history")
        XCTAssertNotNil(updated.lastGoalIncreaseDate, "anchor initialized to now")
    }

    func testIgnoresHabitsWithoutProgression() async throws {
        let repo = InMemoryHabitRepository()
        let habit = Habit(title: "Read", category: .good, goal: 20) // no progression
        try await repo.save(habit)

        await engine(repo).runCatchUp()

        let fetched = try await repo.fetch(id: habit.id)!
        XCTAssertEqual(fetched.goal, 20)
        XCTAssertNil(fetched.lastGoalIncreaseDate)
    }

    func testBoundedByMaxBumpsPerRun() async throws {
        let repo = InMemoryHabitRepository()
        var habit = Habit(title: "Pushups", category: .good, goal: 20,
                          goalProgression: GoalProgression(incrementAmount: 1, intervalDays: 1))
        habit.lastGoalIncreaseDate = daysAgo(1000) // would be 1000 bumps unbounded
        try await repo.save(habit)

        await engine(repo, maxBumps: 10).runCatchUp()

        let goal = try await repo.fetch(id: habit.id)!.goal
        XCTAssertEqual(goal, 30, "20 + capped 10 x 1")
    }
}
