import XCTest
@testable import Forge

/// Prayer completion-window tests (P1 Phase 3), anchored on the same Adhan
/// reference schedule as `PrayerTimeServiceTests` (Raleigh, 2015-12-01, MWL,
/// Shafi'i → Fajr 5:35 / Sunrise 7:06 / Dhuhr 12:05 / Asr 2:42 / Maghrib 5:01
/// / Isha 6:26, America/New_York). The cross-midnight Isha window is the case
/// most worth pinning down.
final class PrayerWindowResolverTests: XCTestCase {

    private let raleigh = Coordinate(latitude: 35.7750, longitude: -78.6336)

    private var nyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func resolver() -> PrayerWindowResolver {
        PrayerWindowResolver(service: AdhanPrayerTimeService(calendar: nyCalendar), calendar: nyCalendar)
    }

    private func day(_ year: Int, _ month: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = d; comps.hour = 12
        return nyCalendar.date(from: comps)!
    }

    private func schedule(_ date: Date) -> PrayerSchedule {
        AdhanPrayerTimeService(calendar: nyCalendar).schedule(for: date, at: raleigh)!
    }

    func testDaytimeWindowsMatchAdjacentPrayerBoundaries() {
        let d = day(2015, 12, 1)
        let s = schedule(d)
        let r = resolver()

        XCTAssertEqual(r.window(for: .fajr, on: d, at: raleigh),
                       PrayerWindow(prayer: .fajr, start: s.fajr, end: s.sunrise))
        XCTAssertEqual(r.window(for: .dhuhr, on: d, at: raleigh),
                       PrayerWindow(prayer: .dhuhr, start: s.dhuhr, end: s.asr))
        XCTAssertEqual(r.window(for: .asr, on: d, at: raleigh),
                       PrayerWindow(prayer: .asr, start: s.asr, end: s.maghrib))
        XCTAssertEqual(r.window(for: .maghrib, on: d, at: raleigh),
                       PrayerWindow(prayer: .maghrib, start: s.maghrib, end: s.isha))
    }

    func testIshaWindowSpansMidnightToNextDayFajr() {
        let d = day(2015, 12, 1)
        let today = schedule(d)
        let tomorrow = schedule(day(2015, 12, 2))
        guard let isha = resolver().window(for: .isha, on: d, at: raleigh) else {
            return XCTFail("no isha window")
        }

        XCTAssertEqual(isha.start, today.isha)
        XCTAssertEqual(isha.end, tomorrow.fajr, "Isha must end at the *next* day's Fajr")
        XCTAssertEqual(isha.preferredEnd, nyCalendar.startOfDay(for: day(2015, 12, 2)),
                       "preferred end is local midnight")
        // The window genuinely crosses midnight: start (evening) < midnight < end (next dawn).
        XCTAssertLessThan(isha.start, isha.preferredEnd!)
        XCTAssertLessThan(isha.preferredEnd!, isha.end)
    }

    func testWindowOpenClosedUpcomingLogic() {
        let d = day(2015, 12, 1)
        let s = schedule(d)
        guard let dhuhr = resolver().window(for: .dhuhr, on: d, at: raleigh) else { return XCTFail() }

        XCTAssertTrue(dhuhr.isUpcoming(at: s.dhuhr.addingTimeInterval(-60)))
        XCTAssertFalse(dhuhr.isOpen(at: s.dhuhr.addingTimeInterval(-60)))

        XCTAssertTrue(dhuhr.isOpen(at: s.dhuhr.addingTimeInterval(60)))
        XCTAssertFalse(dhuhr.isClosed(at: s.dhuhr.addingTimeInterval(60)))

        // At/after Asr start the Dhuhr window is closed → auto-miss condition.
        XCTAssertTrue(dhuhr.isClosed(at: s.asr))
        XCTAssertFalse(dhuhr.isOpen(at: s.asr))
    }

    func testIshaPastPreferredTimeButStillOpen() {
        let d = day(2015, 12, 1)
        guard let isha = resolver().window(for: .isha, on: d, at: raleigh) else { return XCTFail() }
        let justAfterMidnight = isha.preferredEnd!.addingTimeInterval(60)

        // After midnight but before next Fajr: still completable, but "late".
        XCTAssertTrue(isha.isOpen(at: justAfterMidnight))
        XCTAssertFalse(isha.isClosed(at: justAfterMidnight))
        XCTAssertTrue(isha.isPastPreferredTime(at: justAfterMidnight))

        // Before midnight: open and not yet late.
        let beforeMidnight = isha.preferredEnd!.addingTimeInterval(-60)
        XCTAssertTrue(isha.isOpen(at: beforeMidnight))
        XCTAssertFalse(isha.isPastPreferredTime(at: beforeMidnight))

        // Non-Isha prayers never report "past preferred".
        let dhuhr = resolver().window(for: .dhuhr, on: d, at: raleigh)!
        XCTAssertFalse(dhuhr.isPastPreferredTime(at: dhuhr.end.addingTimeInterval(-1)))
    }
}
