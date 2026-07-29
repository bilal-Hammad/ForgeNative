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

    /// A single `swipeLeft()` intermittently fails to register as a swipe
    /// on this List in Simulator (observed directly: one run's injected
    /// swipe produced zero visual change while the identical call passed
    /// twice the same day — XCUITest's own failure recording confirmed the
    /// row never moved a pixel). Slow velocity is recognized more reliably
    /// than the default, and a bounded retry absorbs the residual flake.
    private func revealTrailingSwipeActions(on row: XCUIElement, revealing button: XCUIElement) {
        for _ in 0..<3 {
            row.swipeLeft(velocity: .slow)
            if button.waitForExistence(timeout: 2) { return }
        }
    }

    func testDeletedRowDisappearsQuickly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let row = app.staticTexts["Delete Timing Habit"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "seeded habit row never appeared")

        let deleteSwipeButton = app.buttons["Delete"]
        revealTrailingSwipeActions(on: row, revealing: deleteSwipeButton)
        XCTAssertTrue(deleteSwipeButton.exists, "swipe-to-delete action never appeared")
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

    /// Regression test for the pre-confirmation tap glitch: the swipe
    /// row's Delete button used to be `Button(role: .destructive)`, and
    /// SwiftUI's List treats a destructive-role swipe action as "invoking
    /// this removes the row" — so a tap pre-played the system's removal
    /// transition (red background expanding to full row width, rows below
    /// reflowing upward) before the app's confirmation alert had shown,
    /// then snapped everything back when no data mutation followed.
    /// Frame-by-frame real-device recording evidence in RESULTS.md. The
    /// fix drops the role (keeping `.tint(.red)` for the same look), so
    /// tapping Delete must now do nothing visually beyond presenting the
    /// confirmation alert. XCUITest can't assert on a sub-second visual
    /// flash — the recording evidence covers that — so this asserts the
    /// interaction contract around it: alert appears, Cancel leaves the
    /// row exactly where it was, on two different rows (the glitch was
    /// reproduced on two different list positions).
    func testDeleteButtonShowsConfirmationAndCancelKeepsRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        for title in ["Delete Timing Habit", "Quantity Test Habit"] {
            let row = app.staticTexts[title]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "seeded habit row \(title) never appeared")

            let deleteSwipeButton = app.buttons["Delete"]
            revealTrailingSwipeActions(on: row, revealing: deleteSwipeButton)
            XCTAssertTrue(deleteSwipeButton.exists, "swipe-to-delete action never appeared for \(title)")
            deleteSwipeButton.tap()

            let cancelButton = app.alerts.buttons["Cancel"]
            XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "confirmation alert never appeared for \(title)")
            // Settle time so a concurrent screen recording captures the
            // tap → alert window cleanly for frame analysis.
            Thread.sleep(forTimeInterval: 1)
            cancelButton.tap()

            XCTAssertTrue(row.waitForExistence(timeout: 5), "row \(title) vanished after cancelling the delete confirmation")
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
