import XCTest

/// TEMPORARY — added for the weekly-pager swipe investigation (both
/// directions reported as rubber-banding/snapping back with no advance).
/// Simulator mouse-drag (`cliclick` etc.) doesn't register as a page-swipe
/// gesture on `TabView(.page)` in this environment — confirmed repeatedly in
/// CLAUDE.md's Home weekly strip investigation history — so this uses real
/// XCUITest touch injection instead, which does go through the actual
/// accessibility/touch-event path rather than a synthesized mouse drag.
///
/// Launches with `-uiTesting`, which (see `ForgeApp.init()`) switches to an
/// isolated in-memory SwiftData store seeded with one habit whose
/// `startDate` is 8 weeks back — real history to page into, without ever
/// touching the device's actual habit data.
@MainActor
final class WeeklyPagerSwipeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeBackwardThenForwardRoundTrips() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let dateLabel = app.staticTexts["weeklyStrip.dateLabel"]
        XCTAssertTrue(dateLabel.waitForExistence(timeout: 10), "date label never appeared")
        // TabView(.page) surfaces to accessibility as a CollectionView, not
        // `Other` — confirmed by dumping app.debugDescription this round.
        let tabView = app.collectionViews["weeklyStrip.tabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10), "weekly strip TabView never appeared")

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        func label(daysAgo: Int) -> String {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            return formatter.string(from: date)
        }

        let todayLabel = label(daysAgo: 0)
        XCTAssertEqual(dateLabel.label, todayLabel, "did not start on today's date")

        func swipeAndExpect(_ direction: String, expected: String, step: String) {
            if direction == "back" {
                tabView.swipeRight()
            } else {
                tabView.swipeLeft()
            }
            let deadline = Date().addingTimeInterval(5)
            while dateLabel.label != expected && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertEqual(dateLabel.label, expected, "\(step): expected label to read \(expected) after swiping \(direction), got \(dateLabel.label)")
        }

        swipeAndExpect("back", expected: label(daysAgo: 7), step: "swipe 1 (back)")
        swipeAndExpect("back", expected: label(daysAgo: 14), step: "swipe 2 (back)")
        swipeAndExpect("forward", expected: label(daysAgo: 7), step: "swipe 3 (forward)")
        swipeAndExpect("forward", expected: todayLabel, step: "swipe 4 (forward, back to start)")
    }
}
