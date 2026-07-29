import XCTest

/// Permanent regression test for the delete-habit delay bug: a real-device
/// investigation this session found a multi-second dead pause between
/// confirming "Delete" in the alert and the row actually disappearing,
/// followed by an unanimated instant cut instead of a real removal
/// transition. Root cause (Simulator-measured, since real-device XCUITest
/// automation could not be established this round — see RESULTS.md):
/// `HomeView.delete(_:)` used to await `calendarSyncService.removeSync`,
/// the repository delete, notification/Live Activity cleanup, and a full
/// `reload()` inline, all before the row left `habits`. The fix makes
/// `delete(_:)` remove the row from `habits`/`selectedDayCompletions`
/// immediately (wrapped in `withAnimation`) and dispatches the backend
/// cleanup as a fire-and-forget `Task`, matching `dispatchMilestoneCheck`'s
/// established shape elsewhere in `HomeView.swift`.
///
/// This test can only assert the *timing* bound, not the animation's visual
/// quality — XCUITest has no way to inspect an in-flight SwiftUI transition.
/// It uses the `-uiTesting` seed's "Delete Timing Habit" (`ForgeApp.swift`).
@MainActor
final class DeleteHabitAnimationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeletedRowDisappearsQuickly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let row = app.staticTexts["Delete Timing Habit"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "seeded habit row never appeared")

        row.swipeLeft()
        let deleteSwipeButton = app.buttons["Delete"]
        XCTAssertTrue(deleteSwipeButton.waitForExistence(timeout: 5), "swipe-to-delete action never appeared")
        deleteSwipeButton.tap()

        let alertDeleteButton = app.alerts.buttons["Delete"]
        XCTAssertTrue(alertDeleteButton.waitForExistence(timeout: 5), "delete confirmation alert never appeared")
        alertDeleteButton.tap()

        // Catches the delay regressing again: before this fix, the row
        // stayed on screen for several seconds after confirming delete.
        // A real removal (optimistic + animated) should clear the
        // accessibility hierarchy well within this bound.
        XCTAssertTrue(row.waitForNonExistence(timeout: 2), "row did not disappear within 2s of confirming delete")
    }
}
