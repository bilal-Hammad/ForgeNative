import XCTest

/// Permanent regression test for the opt-in, time-gated Mood Check-In card
/// (§13 + the 2026-07-30 opt-in redesign). The card is now hidden by
/// default, appears only when the "Mood Check-In" Settings toggle is on and
/// its chosen time has passed today, stays until logged, and animates away
/// once a mood is picked. `@AppStorage` reads `UserDefaults.standard`, and
/// `-key value` launch arguments land in the argument domain (highest
/// precedence) — so the toggle and time can be driven deterministically here
/// without touching Settings UI. Uses the same `-uiTesting` in-memory
/// fixture as the other UI tests; real on-device data is never touched.
@MainActor
final class MoodCheckInTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(enabled: Bool, hour: Int, minute: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-moodCheckInReminderEnabled", enabled ? "YES" : "NO",
            "-moodCheckInReminderHour", "\(hour)",
            "-moodCheckInReminderMinute", "\(minute)",
        ]
        app.launch()
        return app
    }

    /// The card element — its heading text is a stable, unique marker.
    private func moodCard(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["How are you feeling today?"]
    }

    /// Default (toggle off): the card must never appear, regardless of time.
    func testCardHiddenWhenFeatureDisabled() throws {
        let app = launch(enabled: false, hour: 0, minute: 0)
        // Give Home a beat to load its list (habits fixture appears).
        XCTAssertTrue(app.staticTexts["Pager Test Habit"].waitForExistence(timeout: 10), "Home never loaded")
        XCTAssertFalse(moodCard(app).exists, "mood card must not appear when the feature is off")
    }

    /// Enabled, chosen time already passed (midnight): the card appears.
    func testCardVisibleWhenEnabledAndTimePassed() throws {
        let app = launch(enabled: true, hour: 0, minute: 0)
        XCTAssertTrue(moodCard(app).waitForExistence(timeout: 10), "mood card should appear when enabled and the time has passed")
    }

    /// Enabled, but the chosen time is late in the day (23:59) so it hasn't
    /// passed yet: the card stays hidden. (Only fails if the test itself runs
    /// in the 23:59 minute — a negligible, documented edge.)
    func testCardHiddenBeforeChosenTime() throws {
        let app = launch(enabled: true, hour: 23, minute: 59)
        XCTAssertTrue(app.staticTexts["Pager Test Habit"].waitForExistence(timeout: 10), "Home never loaded")
        XCTAssertFalse(moodCard(app).exists, "mood card should stay hidden before its chosen time")
    }

    /// Logging a mood dismisses the card (it should not linger after a pick).
    func testLoggingMoodDismissesCard() throws {
        let app = launch(enabled: true, hour: 0, minute: 0)
        let card = moodCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10), "mood card should be visible to log against")

        app.buttons["moodCheckIn.good"].tap()

        // A brief acknowledgement beat (~0.35s) precedes the animated
        // removal, so allow a generous window for the card to leave.
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "card should dismiss after a mood is logged")
    }
}
