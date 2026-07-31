import XCTest

/// Permanent regression test for the pinned timer mini-player bar + its
/// touch-and-hold expanded panel (Feature C redesign, 2026-07-31 — replaced
/// the earlier `.confirmationDialog`). Uses the `-uiTesting` fixture's
/// "Stop Button Test Habit" (goal 2 minutes) so the timer stays active long
/// enough to drive the bar.
@MainActor
final class TimerOptionsSheetTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchAndStartTimer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let row = app.staticTexts["Stop Button Test Habit"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "seeded timer habit row never appeared")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "timer never started")
        return app
    }

    private func miniPlayer(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["timerMiniPlayer"]
    }

    /// The bar appears (pinned) once a timer is running.
    func testMiniPlayerAppearsWhenTimerRunning() throws {
        let app = launchAndStartTimer()
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 5), "mini-player bar never appeared for a running timer")
    }

    /// The in-app pause button pauses the timer (row shows the paused glyph);
    /// tapping again resumes it.
    func testPauseResumeFromBar() throws {
        let app = launchAndStartTimer()
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 5))

        app.buttons["timerMiniPlayer.pauseResume"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.paused"].waitForExistence(timeout: 5), "pause didn't move the timer to the paused state")

        app.buttons["timerMiniPlayer.pauseResume"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "resume didn't return the timer to running")
    }

    /// Touch-and-hold the bar opens the expanded panel with all three rows.
    func testTouchAndHoldShowsPanelOptions() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Complete Now"].firstMatch.waitForExistence(timeout: 5), "expanded panel never appeared")
        XCTAssertTrue(app.buttons["Restart Timer"].firstMatch.exists, "Restart Timer missing")
        XCTAssertTrue(app.buttons["Stop Timer"].firstMatch.exists, "Stop Timer missing")
    }

    /// Stop from the panel cancels the timer (bar disappears, row idle).
    func testStopFromPanel() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.press(forDuration: 0.7)
        let stop = app.buttons["Stop Timer"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.idle"].waitForExistence(timeout: 5), "Stop didn't return the timer to idle")
        XCTAssertFalse(miniPlayer(app).exists, "mini-player should disappear once no timer is active")
    }

    /// Complete Now from the panel completes the habit.
    func testCompleteFromPanel() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.press(forDuration: 0.7)
        let complete = app.buttons["Complete Now"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.complete"].waitForExistence(timeout: 5), "Complete Now didn't complete the habit")
    }

    /// Restart from the panel keeps the timer running (fresh run).
    func testRestartFromPanel() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.press(forDuration: 0.7)
        let restart = app.buttons["Restart Timer"].firstMatch
        XCTAssertTrue(restart.waitForExistence(timeout: 5))
        restart.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "timer should still be running after Restart")
    }
}
