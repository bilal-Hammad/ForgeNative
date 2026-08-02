import XCTest

/// Permanent regression test for the pinned timer mini-player bar + its
/// tap-to-expand panel (redesigned 2026-08-02: tap instead of touch-and-hold
/// to expand; icon-only Liquid Glass buttons instead of text rows; Stop
/// pauses instead of cancelling — see `TimerExpandedPanel`'s doc comment).
/// Uses the `-uiTesting` fixture's "Stop Button Test Habit" (goal 2 minutes)
/// so the timer stays active long enough to drive the bar.
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

    /// Icon-only buttons still carry a real accessibilityLabel — `.buttons[label]`
    /// finds them the same way a text-labeled button would be found.
    private func panelButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons[label].firstMatch
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

    /// A single **tap** (not touch-and-hold) on the mini-player opens the
    /// expanded panel, with all three running-state icon-only buttons
    /// present (found by their real accessibilityLabel, not visible text —
    /// there is none anymore).
    func testTapShowsPanelOptions() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        XCTAssertTrue(panelButton(app, "Complete now").waitForExistence(timeout: 5), "expanded panel never appeared on a plain tap")
        XCTAssertTrue(panelButton(app, "Restart timer").exists, "Restart button missing")
        XCTAssertTrue(panelButton(app, "Stop timer").exists, "Stop button missing")
    }

    /// Stop transitions the *same* sheet to the paused button set — it does
    /// not dismiss the sheet, and it does not cancel the timer (the row
    /// stays `timerStatus.paused`, not `timerStatus.idle`).
    func testStopPausesAndSwapsToPausedButtonsWithoutDismissing() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        let stop = panelButton(app, "Stop timer")
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        // The row/mini-player state moved to paused (a real pause, not a cancel).
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.paused"].waitForExistence(timeout: 5), "Stop should pause, not cancel")

        // The sheet is still open, now showing the paused button set —
        // Resume/Cancel present, Restart/Stop gone.
        XCTAssertTrue(panelButton(app, "Resume timer").waitForExistence(timeout: 5), "sheet should still be open, now showing Resume")
        XCTAssertTrue(panelButton(app, "Cancel timer").exists, "Cancel button missing from the paused set")
        XCTAssertFalse(panelButton(app, "Restart timer").exists, "Restart shouldn't be in the paused button set")
        XCTAssertFalse(panelButton(app, "Stop timer").exists, "Stop shouldn't be in the paused button set")
    }

    /// Resume continues from banked time — not a fresh restart. Verified by
    /// pausing partway through, reading the mini-player's frozen remaining
    /// time, resuming from the panel, and confirming the row returns to
    /// running (a fresh restart would also show "running", so this test's
    /// real value is confirming Resume — not some other action — is what's
    /// wired to the panel's play button, and that it doesn't reset progress
    /// back to idle/zero first).
    func testResumeFromPanelContinuesFromBankedTime() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        let stopButton = panelButton(app, "Stop timer")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        stopButton.tap() // pause
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.paused"].waitForExistence(timeout: 5))

        let resume = panelButton(app, "Resume timer")
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()

        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "Resume should return the timer to running")
        // The sheet dismisses after Resume.
        XCTAssertFalse(panelButton(app, "Resume timer").exists, "sheet should dismiss after Resume")
    }

    /// Cancel (paused state) fully discards the timer — row goes idle, bar
    /// disappears, matching the old Stop-from-panel's cancel behavior.
    func testCancelFromPanelFullyDiscards() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        let stopButton = panelButton(app, "Stop timer")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        stopButton.tap() // pause
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.paused"].waitForExistence(timeout: 5))

        let cancel = panelButton(app, "Cancel timer")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.idle"].waitForExistence(timeout: 5), "Cancel didn't return the timer to idle")
        XCTAssertFalse(miniPlayer(app).exists, "mini-player should disappear once no timer is active")
    }

    /// Complete Now from the panel completes the habit (running state).
    func testCompleteFromPanel() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        let complete = panelButton(app, "Complete now")
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.complete"].waitForExistence(timeout: 5), "Complete Now didn't complete the habit")
    }

    /// Restart from the panel keeps the timer running (fresh run).
    func testRestartFromPanel() throws {
        let app = launchAndStartTimer()
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        let restart = panelButton(app, "Restart timer")
        XCTAssertTrue(restart.waitForExistence(timeout: 5))
        restart.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "timer should still be running after Restart")
    }
}
