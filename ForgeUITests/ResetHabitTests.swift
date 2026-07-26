import XCTest

/// Real-touch-injected regression test for the context-aware long-press
/// Complete/Reset feature: no progress → instant complete (unchanged);
/// partial progress → a dialog offering Complete or Reset; already
/// complete → the same dialog with only Reset. Uses the `-uiTesting`
/// fixture's seeded "Quantity Test Habit" (goal 3, plain count) and
/// "Timer Test Habit" (goal 0.05 minutes = 3 real seconds — see
/// `ForgeApp.swift`'s `-uiTesting` seed block).
@MainActor
final class ResetHabitTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testQuantityHabitPartialProgressDialogAndReset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let habitRow = app.staticTexts["Quantity Test Habit"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 10))

        let progress = app.descendants(matching: .any)["quantityProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "0 of 3")

        // Two taps: partial progress (2 of 3), not yet complete.
        habitRow.tap()
        habitRow.tap()
        XCTAssertEqual(progress.label, "2 of 3")

        // Long-press with partial progress should offer both options.
        habitRow.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Complete"].waitForExistence(timeout: 5), "Complete option should appear with partial progress")
        XCTAssertTrue(app.buttons["Reset"].exists)

        app.buttons["Reset"].tap()

        let deadline = Date().addingTimeInterval(5)
        while progress.label != "0 of 3" && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(progress.label, "0 of 3", "Reset should zero the count back out")
    }

    func testQuantityHabitCompleteDialogOffersOnlyReset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let habitRow = app.staticTexts["Quantity Test Habit"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 10))

        // Long-press with zero progress instantly completes (unchanged
        // behavior) — no dialog at all.
        habitRow.press(forDuration: 0.6)
        XCTAssertFalse(app.buttons["Reset"].waitForExistence(timeout: 2), "No-progress long-press should instantly complete, not show a dialog")

        let progress = app.descendants(matching: .any)["quantityProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "3 of 3")

        // Long-press again, now complete — only Reset should be offered.
        habitRow.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Reset"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Complete"].exists, "Complete shouldn't be offered once already complete")

        app.buttons["Reset"].tap()
        let deadline = Date().addingTimeInterval(5)
        while progress.label != "0 of 3" && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(progress.label, "0 of 3")
    }

    func testTimerHabitRunningLongPressDialogAndReset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let habitRow = app.staticTexts["Timer Test Habit"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 10))

        habitRow.tap()
        let runningMarker = app.descendants(matching: .any)["timerStatus.running"]
        XCTAssertTrue(runningMarker.waitForExistence(timeout: 5))

        // Long-press a running timer: partial progress, both options.
        habitRow.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reset"].exists)

        app.buttons["Reset"].tap()

        let idleMarker = app.descendants(matching: .any)["timerStatus.idle"]
        XCTAssertTrue(idleMarker.waitForExistence(timeout: 5), "Reset should cancel the running timer back to idle")
        XCTAssertFalse(app.descendants(matching: .any)["timerStatus.running"].exists)
    }
}
