import XCTest

/// Permanent regression test for the running-timer options sheet (Feature C,
/// 2026-07-30): tapping a running timer's countdown ring opens a native
/// `.confirmationDialog` with Complete Now / Restart Timer / Stop Timer
/// (destructive). Uses the `-uiTesting` fixture's "Stop Button Test Habit"
/// (goal 2 minutes) so the timer stays running long enough to drive the
/// sheet.
///
/// Two real XCUITest facts about `.confirmationDialog` on iOS 26, both
/// confirmed from a captured accessibility hierarchy (not guessed):
/// - each action button is registered *twice* in the tree, so queries use
///   `.firstMatch` to avoid "multiple matching elements";
/// - it renders here as an anchored menu-style sheet that dismisses by
///   tapping outside rather than exposing a labeled "Cancel" button — so the
///   dismiss case taps outside the sheet, which is this rendering's Cancel.
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

    private func openSheet(_ app: XCUIApplication) {
        app.buttons["timerStatus.running"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Complete Now"].firstMatch.waitForExistence(timeout: 5), "options sheet never opened")
    }

    func testSheetShowsAllThreeOptions() throws {
        let app = launchAndStartTimer()
        openSheet(app)
        XCTAssertTrue(app.buttons["Complete Now"].firstMatch.exists, "Complete Now missing")
        XCTAssertTrue(app.buttons["Restart Timer"].firstMatch.exists, "Restart Timer missing")
        XCTAssertTrue(app.buttons["Stop Timer"].firstMatch.exists, "Stop Timer missing")
    }

    /// Dismissing without choosing an option (tapping outside the menu-style
    /// sheet — this rendering's Cancel) leaves the timer running.
    func testDismissKeepsTimerRunning() throws {
        let app = launchAndStartTimer()
        openSheet(app)
        // Tap near the very top, outside the anchored sheet, to dismiss.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "timer should still be running after dismissing the sheet")
    }

    func testCompleteNowCompletesHabit() throws {
        let app = launchAndStartTimer()
        openSheet(app)
        app.buttons["Complete Now"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.complete"].waitForExistence(timeout: 5), "Complete Now didn't complete the habit")
    }

    func testRestartKeepsTimerRunning() throws {
        let app = launchAndStartTimer()
        openSheet(app)
        app.buttons["Restart Timer"].firstMatch.tap()
        // The seed has another, unrelated idle timer habit, so a global
        // `timerStatus.idle` check would be a false positive — the meaningful
        // assertion is simply that this habit's timer is running post-restart.
        XCTAssertTrue(app.descendants(matching: .any)["timerStatus.running"].waitForExistence(timeout: 5), "timer should still be running after Restart")
    }
}
