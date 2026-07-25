import XCTest

/// TEMPORARY — quick real-touch-injected verification that the mood
/// check-in card's log flow actually works end to end (tap → selected
/// state updates immediately, no confirmation screen), for the Progress
/// redesign + mood check-in feature build. Uses the same `-uiTesting`
/// in-memory fixture as `WeeklyPagerSwipeTests` — real on-device data is
/// never touched.
@MainActor
final class MoodCheckInTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingMoodOptionSelectsItImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let goodButton = app.buttons["moodCheckIn.good"]
        XCTAssertTrue(goodButton.waitForExistence(timeout: 10), "mood check-in card never appeared")
        XCTAssertFalse(goodButton.isSelected, "should start unselected — today not logged yet in a fresh fixture")

        goodButton.tap()

        let deadline = Date().addingTimeInterval(5)
        while !goodButton.isSelected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(goodButton.isSelected, "tapping Good should select it immediately, no confirmation step")

        // Switching to a different option should overwrite, not stack.
        let greatButton = app.buttons["moodCheckIn.great"]
        greatButton.tap()
        let deadline2 = Date().addingTimeInterval(5)
        while !greatButton.isSelected && Date() < deadline2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(greatButton.isSelected, "tapping a different option should switch selection")
        XCTAssertFalse(goodButton.isSelected, "the previous selection should no longer read as selected")
    }
}
