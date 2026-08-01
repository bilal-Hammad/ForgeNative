import XCTest
@testable import Forge

/// Tests the self-healing auto-miss catch-up (P1 Phase 3): closed, uncompleted
/// prayer windows get persisted as `missed`; completed days and still-open
/// windows are left alone; and it's bounded to the lookback. Uses the real
/// `AdhanPrayerTimeService` + `InMemoryHabitRepository` with relative dates
/// (Fajr's window is always a morning window, closed by an evening `now`), so
/// it's deterministic regardless of the machine's timezone.
final class PrayerWindowCatchUpTests: XCTestCase {

    private let raleigh = Coordinate(latitude: 35.7750, longitude: -78.6336)
    private let calendar = Calendar.current

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: Date()))!
    }

    /// This evening — every prayer window for today and earlier has closed.
    private func thisEvening() -> Date {
        calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!
    }

    private func makeCatchUp(_ repo: InMemoryHabitRepository, lookbackDays: Int = 7) -> PrayerWindowCatchUp {
        PrayerWindowCatchUp(
            habitRepository: repo,
            resolver: PrayerWindowResolver(service: AdhanPrayerTimeService(), calendar: calendar),
            calendar: calendar,
            lookbackDays: lookbackDays
        )
    }

    func testMarksClosedUncompletedWindowsAsMissedButLeavesCompletedDays() async throws {
        let repo = InMemoryHabitRepository()
        let fajr = Habit(title: "Fajr", category: .good,
                         timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr)),
                         startDate: daysAgo(4))
        try await repo.save(fajr)

        // The user completed Fajr 2 days ago — must NOT be flipped to missed.
        try await repo.upsertCompletion(Completion(habitID: fajr.id, date: daysAgo(2), isComplete: true))

        await makeCatchUp(repo).run(coordinate: raleigh, asOf: thisEvening())

        let completions = try await repo.fetchCompletions(habitID: fajr.id, from: daysAgo(10), to: Date())
        let byDay = Dictionary(uniqueKeysWithValues: completions.map { (calendar.startOfDay(for: $0.date), $0) })

        // 4 days ago, 3, 1, and today: closed Fajr window, no completion → missed.
        for n in [4, 3, 1, 0] {
            let c = byDay[daysAgo(n)]
            XCTAssertEqual(c?.missed, true, "day -\(n) should be missed")
            XCTAssertEqual(c?.isComplete, false, "a missed day is not complete")
        }
        // 2 days ago stays completed, never missed.
        XCTAssertEqual(byDay[daysAgo(2)]?.isComplete, true)
        XCTAssertEqual(byDay[daysAgo(2)]?.missed, false)
    }

    func testDoesNotTouchNonPrayerHabits() async throws {
        let repo = InMemoryHabitRepository()
        let normal = Habit(title: "Read", category: .good, startDate: daysAgo(4)) // timeMode .none
        try await repo.save(normal)

        await makeCatchUp(repo).run(coordinate: raleigh, asOf: thisEvening())

        let completions = try await repo.fetchCompletions(habitID: normal.id, from: daysAgo(10), to: Date())
        XCTAssertTrue(completions.isEmpty, "a non-prayer habit must never get auto-missed completions")
    }

    func testIsBoundedByLookback() async throws {
        let repo = InMemoryHabitRepository()
        let fajr = Habit(title: "Fajr", category: .good,
                         timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr)),
                         startDate: daysAgo(30))
        try await repo.save(fajr)

        await makeCatchUp(repo, lookbackDays: 3).run(coordinate: raleigh, asOf: thisEvening())

        let completions = try await repo.fetchCompletions(habitID: fajr.id, from: daysAgo(60), to: Date())
        // Only the last 3 days (+ today) are swept — nothing older than the lookback.
        let oldest = completions.map { calendar.startOfDay(for: $0.date) }.min()
        XCTAssertNotNil(oldest)
        XCTAssertGreaterThanOrEqual(oldest!, daysAgo(3))
    }

    func testIdempotentAndDoesNotReopenExistingMiss() async throws {
        let repo = InMemoryHabitRepository()
        let fajr = Habit(title: "Fajr", category: .good,
                         timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr)),
                         startDate: daysAgo(3))
        try await repo.save(fajr)

        let catchUp = makeCatchUp(repo)
        await catchUp.run(coordinate: raleigh, asOf: thisEvening())
        let firstPass = try await repo.fetchCompletions(habitID: fajr.id, from: daysAgo(10), to: Date())
        await catchUp.run(coordinate: raleigh, asOf: thisEvening())
        let secondPass = try await repo.fetchCompletions(habitID: fajr.id, from: daysAgo(10), to: Date())

        XCTAssertEqual(firstPass.count, secondPass.count, "a second sweep must not create duplicate rows")
        XCTAssertTrue(secondPass.allSatisfy { $0.missed })
    }
}
