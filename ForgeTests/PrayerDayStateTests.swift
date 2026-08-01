import XCTest
@testable import Forge

/// Tests the pure prayer day-state resolution (P1 Phase 3) — the logic that
/// decides whether a prayer-relative habit's row is upcoming / completable /
/// late / completed / missed-locked.
final class PrayerDayStateTests: XCTestCase {

    private let habitID = UUID()
    private let day = Date(timeIntervalSince1970: 1_450_000_000)

    private func window(start: Date, end: Date, preferredEnd: Date? = nil) -> PrayerWindow {
        PrayerWindow(prayer: .dhuhr, start: start, end: end, preferredEnd: preferredEnd)
    }

    private func completion(isComplete: Bool = false, missed: Bool = false) -> Completion {
        Completion(habitID: habitID, date: day, isComplete: isComplete, missed: missed)
    }

    func testUpcomingBeforeWindowOpens() {
        let now = Date(timeIntervalSince1970: 1000)
        let w = window(start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(PrayerDayState.resolve(window: w, completion: nil, now: now), .upcoming)
        XCTAssertFalse(PrayerDayState.resolve(window: w, completion: nil, now: now).isCompletable)
    }

    func testOpenWithinWindow() {
        let now = Date(timeIntervalSince1970: 2500)
        let w = window(start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 3000))
        let state = PrayerDayState.resolve(window: w, completion: nil, now: now)
        XCTAssertEqual(state, .open)
        XCTAssertTrue(state.isCompletable)
    }

    func testMissedWhenWindowClosedUncompleted() {
        let now = Date(timeIntervalSince1970: 4000)
        let w = window(start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 3000))
        let state = PrayerDayState.resolve(window: w, completion: nil, now: now)
        XCTAssertEqual(state, .missed)
        XCTAssertTrue(state.isMissedLocked)
        XCTAssertFalse(state.isCompletable)
    }

    func testCompletedWinsRegardlessOfTime() {
        // Even long after the window, a completed prayer stays completed.
        let now = Date(timeIntervalSince1970: 99_999)
        let w = window(start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(PrayerDayState.resolve(window: w, completion: completion(isComplete: true), now: now), .completed)
    }

    func testPersistedMissedIsAuthoritative() {
        // A persisted miss stays missed even if a recomputed window (e.g. after
        // a location change) would now look open.
        let now = Date(timeIntervalSince1970: 2500)
        let w = window(start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(PrayerDayState.resolve(window: w, completion: completion(missed: true), now: now), .missed)
    }

    func testOpenLateForIshaPastMidnight() {
        let start = Date(timeIntervalSince1970: 2000)
        let midnight = Date(timeIntervalSince1970: 3000)
        let end = Date(timeIntervalSince1970: 4000)
        let w = PrayerWindow(prayer: .isha, start: start, end: end, preferredEnd: midnight)
        // Before midnight → open; after midnight but before end → openLate.
        XCTAssertEqual(PrayerDayState.resolve(window: w, completion: nil, now: Date(timeIntervalSince1970: 2500)), .open)
        XCTAssertEqual(PrayerDayState.resolve(window: w, completion: nil, now: Date(timeIntervalSince1970: 3500)), .openLate)
        XCTAssertTrue(PrayerDayState.resolve(window: w, completion: nil, now: Date(timeIntervalSince1970: 3500)).isCompletable)
    }

    func testNilWindowDegradesToCompletable() {
        // No location/schedule → don't block or falsely miss; allow completion.
        XCTAssertEqual(PrayerDayState.resolve(window: nil, completion: nil, now: .now), .open)
    }
}
