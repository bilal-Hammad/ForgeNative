import XCTest
@testable import Forge

/// Phase 4 tests: the pure fire-time computation, the per-prayer offset
/// defaults, and — most importantly — the **independence invariant**: no
/// notification setting may weaken Phase 3's completion-window lock.
final class PrayerNotificationSchedulerTests: XCTestCase {

    private let raleigh = Coordinate(latitude: 35.7750, longitude: -78.6336)

    private var nyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = hour
        return nyCalendar.date(from: comps)!
    }

    // MARK: Offsets

    func testDefaultOffsetsMatchSpec() {
        XCTAssertEqual(PrayerPreferences.defaultOffsets(for: .fajr), PrayerOffsets(iqamaDelayMinutes: 30, prayerDurationMinutes: 20))
        XCTAssertEqual(PrayerPreferences.defaultOffsets(for: .fajr).totalMinutes, 50)
        for prayer in [PrayerName.dhuhr, .asr, .maghrib, .isha] {
            XCTAssertEqual(PrayerPreferences.defaultOffsets(for: prayer), PrayerOffsets(iqamaDelayMinutes: 10, prayerDurationMinutes: 15))
            XCTAssertEqual(PrayerPreferences.defaultOffsets(for: prayer).totalMinutes, 25)
        }
    }

    func testOffsetsRoundTripThroughPreferences() {
        let original = PrayerPreferences.offsets(for: .maghrib)
        defer { PrayerPreferences.setOffsets(original, for: .maghrib) }

        PrayerPreferences.setOffsets(PrayerOffsets(iqamaDelayMinutes: 5, prayerDurationMinutes: 8), for: .maghrib)
        XCTAssertEqual(PrayerPreferences.offsets(for: .maghrib), PrayerOffsets(iqamaDelayMinutes: 5, prayerDurationMinutes: 8))
    }

    // MARK: Fire-time computation

    func testFireDateIsAdhanPlusTotalOffset() {
        let service = AdhanPrayerTimeService(calendar: nyCalendar)
        let d = day(2015, 12, 1)
        let schedule = service.schedule(for: d, at: raleigh)!
        let offsets = PrayerOffsets(iqamaDelayMinutes: 10, prayerDurationMinutes: 15) // 25 min

        let fire = PrayerNotificationScheduler.fireDate(
            anchor: PrayerAnchor(prayer: .dhuhr), offsets: offsets,
            day: d, coordinate: raleigh, service: service
        )
        XCTAssertEqual(fire, schedule.dhuhr.addingTimeInterval(25 * 60))
    }

    func testUpcomingFireDatesAreFutureAndChronological() {
        let service = AdhanPrayerTimeService(calendar: nyCalendar)
        // 3am NY, before Fajr — so today's Fajr notification is still upcoming.
        let now = day(2015, 12, 1, hour: 3)
        let dates = PrayerNotificationScheduler.upcomingFireDates(
            anchor: PrayerAnchor(prayer: .fajr),
            offsets: PrayerPreferences.defaultOffsets(for: .fajr),
            coordinate: raleigh, service: service, calendar: nyCalendar, now: now, daysAhead: 3
        )
        XCTAssertEqual(dates.count, 3)
        XCTAssertTrue(dates.allSatisfy { $0 > now }, "every scheduled fire date must be in the future")
        XCTAssertEqual(dates, dates.sorted(), "fire dates must be chronological")
    }

    // MARK: Independence invariant (Phase 4 clarification)

    /// A prayer habit with notifications turned OFF must still be auto-missed
    /// when its window closes — the lock is fully independent of notification
    /// settings.
    func testNotificationsOffDoesNotWeakenWindowLock() async throws {
        let repo = InMemoryHabitRepository()
        let calendar = Calendar.current
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: calendar.startOfDay(for: Date()))!
        var fajr = Habit(title: "Fajr", category: .good,
                         timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr)),
                         startDate: fourDaysAgo)
        fajr.notificationsEnabled = false // notifications OFF
        try await repo.save(fajr)

        let catchUp = PrayerWindowCatchUp(
            habitRepository: repo,
            resolver: PrayerWindowResolver(service: AdhanPrayerTimeService(), calendar: calendar),
            calendar: calendar
        )
        let thisEvening = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!
        await catchUp.run(coordinate: raleigh, asOf: thisEvening)

        let completions = try await repo.fetchCompletions(habitID: fajr.id, from: calendar.date(byAdding: .day, value: -10, to: Date())!, to: Date())
        XCTAssertTrue(completions.contains { $0.missed }, "window lock must apply even with notifications off")
    }
}
