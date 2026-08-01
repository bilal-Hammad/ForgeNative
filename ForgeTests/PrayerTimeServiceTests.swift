import XCTest
@testable import Forge

/// Prayer-time accuracy + prayer-anchor resolution tests (P1 Phase 2). The
/// accuracy assertions mirror Adhan Swift's own documented reference case
/// (coordinates 35.7750/-78.6336, 2015-12-01, Muslim World League method,
/// **Shafi'i** madhab, America/New_York) — which is exactly this service's
/// default configuration — so this verifies both that Adhan is wired
/// correctly (right prayer mapped to the right property, not swapped) and
/// that the Shafi'i madhab is actually applied (a Hanafi Asr would be
/// materially later than the asserted 2:42 PM).
final class PrayerTimeServiceTests: XCTestCase {

    private let raleigh = Coordinate(latitude: 35.7750, longitude: -78.6336)

    /// A gregorian calendar fixed to America/New_York, so day extraction and
    /// the input date are deterministic regardless of the test machine's zone.
    private var nyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        return nyCalendar.date(from: comps)!
    }

    private func nyTimeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")!
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }

    func testScheduleMatchesKnownShafiReferenceValues() {
        let service = AdhanPrayerTimeService(calendar: nyCalendar) // MWL + Shafi'i defaults
        guard let schedule = service.schedule(for: date(year: 2015, month: 12, day: 1), at: raleigh) else {
            return XCTFail("Adhan returned no schedule for a normal mid-latitude date")
        }
        let f = nyTimeFormatter()
        XCTAssertEqual(f.string(from: schedule.fajr), "5:35 AM")
        XCTAssertEqual(f.string(from: schedule.sunrise), "7:06 AM")
        XCTAssertEqual(f.string(from: schedule.dhuhr), "12:05 PM")
        XCTAssertEqual(f.string(from: schedule.asr), "2:42 PM", "Asr must use the Shafi'i madhab")
        XCTAssertEqual(f.string(from: schedule.maghrib), "5:01 PM")
        XCTAssertEqual(f.string(from: schedule.isha), "6:26 PM")
    }

    func testPrayerTimesAreChronological() {
        let service = AdhanPrayerTimeService(calendar: nyCalendar)
        guard let s = service.schedule(for: date(year: 2015, month: 12, day: 1), at: raleigh) else {
            return XCTFail("no schedule")
        }
        XCTAssertLessThan(s.fajr, s.sunrise)
        XCTAssertLessThan(s.sunrise, s.dhuhr)
        XCTAssertLessThan(s.dhuhr, s.asr)
        XCTAssertLessThan(s.asr, s.maghrib)
        XCTAssertLessThan(s.maghrib, s.isha)
    }

    func testScheduleTimeForPrayerMapsCorrectly() {
        let service = AdhanPrayerTimeService(calendar: nyCalendar)
        guard let s = service.schedule(for: date(year: 2015, month: 12, day: 1), at: raleigh) else {
            return XCTFail("no schedule")
        }
        XCTAssertEqual(s.time(for: .fajr), s.fajr)
        XCTAssertEqual(s.time(for: .dhuhr), s.dhuhr)
        XCTAssertEqual(s.time(for: .asr), s.asr)
        XCTAssertEqual(s.time(for: .maghrib), s.maghrib)
        XCTAssertEqual(s.time(for: .isha), s.isha)
    }

    func testResolvedTimeAppliesSignedOffset() {
        let service = AdhanPrayerTimeService(calendar: nyCalendar)
        let day = date(year: 2015, month: 12, day: 1)
        guard let s = service.schedule(for: day, at: raleigh) else { return XCTFail("no schedule") }

        // "10 minutes before Dhuhr" (a rawatib sunnah) resolves to dhuhr - 600s.
        let before = PrayerAnchor(prayer: .dhuhr, offsetMinutes: -10)
        XCTAssertEqual(service.resolvedTime(for: before, on: day, at: raleigh),
                       s.dhuhr.addingTimeInterval(-600))

        // "At Maghrib" (offset 0) resolves to exactly the adhan time.
        let atMaghrib = PrayerAnchor(prayer: .maghrib, offsetMinutes: 0)
        XCTAssertEqual(service.resolvedTime(for: atMaghrib, on: day, at: raleigh), s.maghrib)

        // "5 minutes after Isha" resolves to isha + 300s.
        let afterIsha = PrayerAnchor(prayer: .isha, offsetMinutes: 5)
        XCTAssertEqual(service.resolvedTime(for: afterIsha, on: day, at: raleigh),
                       s.isha.addingTimeInterval(300))
    }

    func testPrayerAnchorDisplayDescription() {
        XCTAssertEqual(PrayerAnchor(prayer: .fajr, offsetMinutes: 0).displayDescription, "At Fajr")
        XCTAssertEqual(PrayerAnchor(prayer: .dhuhr, offsetMinutes: -10).displayDescription, "10 min before Dhuhr")
        XCTAssertEqual(PrayerAnchor(prayer: .maghrib, offsetMinutes: 5).displayDescription, "5 min after Maghrib")
    }
}
