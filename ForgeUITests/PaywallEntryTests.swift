import XCTest

/// Verifies the paywall is actually reachable from a real navigation entry
/// point (P1 Phase 8 wiring-gap fix, 2026-08-02) — the general "Upgrade to
/// Forge Premium" card in Profile, which previously did not exist (PaywallView
/// was only reachable via the deep Add-Section flow). Real touch injection.
@MainActor
final class PaywallEntryTests: XCTestCase {

    func testProfilePremiumCardOpensPaywall() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] // stub entitlement (not premium) → the upgrade card shows
        app.launch()

        app.tabBars.buttons["Profile"].firstMatch.tap()

        let upgrade = app.buttons["profile.upgradeToPremium"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10), "the Upgrade to Forge Premium card should be on the Profile screen")
        upgrade.tap()

        // The paywall sheet is up — its Restore Purchases button is unique to it.
        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 5), "tapping the card should open PaywallView")
    }
}
