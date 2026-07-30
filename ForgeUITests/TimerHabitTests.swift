import XCTest

/// Real-touch-injected regression test for the time-unit habit timer
/// feature (a habit whose `unit` is `.minutes`/`.hours` — see
/// `HabitUnit.isTimeBased`): tapping starts a native countdown that
/// completes on its own once the goal duration passes, and long-press
/// still instantly force-completes without ever touching the timer. Uses
/// the `-uiTesting` in-memory fixture's seeded "Timer Test Habit" (goal
/// 0.05 minutes = 3 real seconds — see `ForgeApp.swift`'s `-uiTesting`
/// seed block — short enough to genuinely reach its goal within a normal
/// test timeout instead of needing a multi-minute wait).
@MainActor
final class TimerHabitTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimerStartsAndCompletesOnItsOwn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let habitRow = app.staticTexts["Timer Test Habit"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 10), "seeded timer habit row never appeared")

        // Idle state before any interaction.
        let idleMarker = app.descendants(matching: .any)["timerStatus.idle"]
        XCTAssertTrue(idleMarker.waitForExistence(timeout: 5), "expected the idle timer marker before tapping")

        habitRow.tap()

        // Running state immediately after the tap — the native
        // ProgressView/Text(timerInterval:) ring should now be showing.
        let runningMarker = app.descendants(matching: .any)["timerStatus.running"]
        XCTAssertTrue(runningMarker.waitForExistence(timeout: 5), "timer never entered the running state after tapping")

        // No further interaction — the 3-second goal should complete on
        // its own via the one-shot scheduled completion.
        let completeMarker = app.descendants(matching: .any)["timerStatus.complete"]
        XCTAssertTrue(completeMarker.waitForExistence(timeout: 10), "timer never reached the complete state on its own")
    }

    func testLongPressInstantlyCompletesWithoutTimer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let habitRow = app.staticTexts["Timer Test Habit"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 10), "seeded timer habit row never appeared")

        habitRow.press(forDuration: 0.6)

        // Should jump straight to complete — never passing through the
        // running state at all (long-press bypasses the timer entirely).
        let completeMarker = app.descendants(matching: .any)["timerStatus.complete"]
        XCTAssertTrue(completeMarker.waitForExistence(timeout: 5), "long-press never instantly completed the timer habit")

        let runningMarker = app.descendants(matching: .any)["timerStatus.running"]
        XCTAssertFalse(runningMarker.exists, "long-press should never leave the timer in a running state")
    }

    /// Regression test for stopping a running timer — now reached through
    /// the running-timer options sheet (Feature C, 2026-07-30) rather than a
    /// standalone Stop button. Tapping the running countdown ring
    /// (`timerStatus.running`, now a Button) opens the
    /// `.confirmationDialog`; its "Stop Timer" (destructive) option cancels
    /// the timer back to idle.
    ///
    /// Uses "Stop Button Test Habit" (goal 2 minutes), not "Timer Test
    /// Habit" (goal 3 seconds) — the 3-second habit auto-completes out from
    /// under the test before it can drive the sheet.
    func testStopOptionStopsRunningTimer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let habitRow = app.staticTexts["Stop Button Test Habit"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 10), "seeded timer habit row never appeared")

        habitRow.tap()
        let runningMarker = app.descendants(matching: .any)["timerStatus.running"]
        XCTAssertTrue(runningMarker.waitForExistence(timeout: 5), "timer never entered the running state after tapping")

        app.buttons["timerStatus.running"].firstMatch.tap()
        let stopOption = app.buttons["Stop Timer"].firstMatch
        XCTAssertTrue(stopOption.waitForExistence(timeout: 5), "options sheet's Stop Timer never appeared")
        stopOption.tap()

        let idleMarker = app.descendants(matching: .any)["timerStatus.idle"]
        XCTAssertTrue(idleMarker.waitForExistence(timeout: 5), "Stop never returned the timer to idle")
        XCTAssertFalse(app.descendants(matching: .any)["timerStatus.running"].exists, "timer should no longer be running after Stop")
    }
}
