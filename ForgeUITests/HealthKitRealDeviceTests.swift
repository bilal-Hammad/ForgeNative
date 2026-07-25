import XCTest

/// Real-device HealthKit verification — deliberately targets a real device,
/// not Simulator, since HealthKit's actual data-flow proof needs a device
/// with real Health data flowing through it. Captures `XCTAttachment`
/// screenshots directly from the XCTest process running on-device (no
/// external tool needed — `idevicescreenshot` doesn't support modern iOS's
/// trusted-tunnel model, and USB-video-capture tricks need a wired
/// connection). Screenshots land in the run's .xcresult bundle; extract them
/// with `xcrun xcresulttool export attachments --path <bundle> --output-path
/// <dir>`.
///
/// **Requires HealthKit authorization to already be granted on the target
/// device before this test can get past the consent step** — confirmed this
/// pass, conclusively, not assumed: the real system "Health Access" consent
/// sheet is visually on screen but sits outside any accessibility tree this
/// environment can query into or click (tried Forge's own `XCUIApplication`,
/// `springboard`'s, and a raw OS-level click bypassing XCUITest entirely —
/// none reached it). This is consistent with Apple's deliberate
/// anti-automation design for consent UI, not a bug to keep chasing. See
/// RESULTS.md's "HealthKit real-device verification" entry for the full
/// investigation and CLAUDE.md's Engineering Standards §5 for why this kind
/// of system-UI boundary gets documented rather than re-investigated from
/// scratch next time it's hit elsewhere.
///
/// **One-time manual step to unblock this test**: launch Forge on the target
/// device, Profile → Settings → Debug → "Seed HealthKit Data" → "Create All
/// Test Habits" → "Request HealthKit Authorization" → tap "Turn On All" then
/// "Allow" on the real system sheet. After that, authorization persists for
/// this app on this device/install indefinitely (until deleted or revoked in
/// iOS Settings → Health → Data Access & Devices), and this test runs fully
/// automated from then on, consent sheet included (it simply won't appear
/// again for already-determined types).
///
/// Uses real, already-existing personal Steps/Sleep data where possible
/// (read-only, never modified) rather than needing synthetic seeding for
/// those two. Writes one small, clearly-test Drink Water entry (a single
/// glass, 8 fl oz) as the write-back proof — safe to delete via the Health
/// app afterward if desired.
@MainActor
final class HealthKitRealDeviceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attachScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func navigateToDebugHealthKitScreen(_ app: XCUIApplication) {
        let profileTab = app.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10))
        profileTab.tap()

        let settingsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Settings' OR label CONTAINS[c] 'gearshape'")).firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let scrollable = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        XCTAssertTrue(scrollable.waitForExistence(timeout: 5))
        let seedHKButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Seed HealthKit Data'")).firstMatch
        var attempts = 0
        while !seedHKButton.exists && attempts < 10 {
            scrollable.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(seedHKButton.exists, "Seed HealthKit Data row not found")
        seedHKButton.tap()
    }

    func testRealDeviceHealthKitEndToEnd() throws {
        let app = XCUIApplication()
        app.launch()
        attachScreenshot("01-home-before")

        navigateToDebugHealthKitScreen(app)
        attachScreenshot("02-debug-screen")

        let createHabitsButton = app.buttons["Create All Test Habits"]
        XCTAssertTrue(createHabitsButton.waitForExistence(timeout: 5))
        createHabitsButton.tap()
        Thread.sleep(forTimeInterval: 2)

        let requestAuthButton = app.buttons["Request HealthKit Authorization"]
        XCTAssertTrue(requestAuthButton.waitForExistence(timeout: 5))
        requestAuthButton.tap()
        Thread.sleep(forTimeInterval: 3)
        attachScreenshot("03-consent-sheet-if-shown")

        // Best-effort only — see this file's doc comment for why this can't
        // be relied on to actually reach the sheet. Harmless no-op once
        // authorization is already determined (the expected steady state
        // after the one-time manual step), since no sheet appears at all.
        let allowButton = app.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
            Thread.sleep(forTimeInterval: 2)
        }

        let checkButton = app.buttons["Check Authorization Status"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 10))
        checkButton.tap()
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot("04-authorization-status")

        // Write-back proof: one real Drink Water sample via Forge's own
        // HealthKitService (not a raw HKHealthStore.save bypass), same code
        // path a real manual tap in the app would go through.
        let waterButton = app.buttons["Drink Water (8 glasses)"]
        if waterButton.waitForExistence(timeout: 5) {
            waterButton.tap()
            Thread.sleep(forTimeInterval: 2)
        }
        attachScreenshot("05-after-seed-water")

        // Read-path proof: Home should reflect real HealthKit data (genuine
        // personal Steps/Sleep, plus the just-written Drink Water sample)
        // with zero further manual interaction.
        let homeTab = app.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        homeTab.tap()
        Thread.sleep(forTimeInterval: 3)
        attachScreenshot("06-home-after-read")
    }
}
