import XCTest

/// Automated screenshot capture for App Store submissions.
/// Run with: `fastlane snapshot` or directly via Xcode test plan.
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Screenshot Sequence

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-screenshot-data"]
        setupSnapshot(app)
        app.launch()

        // Allow data to seed and UI to settle
        sleep(3)

        // 1. Dashboard — the hero screenshot
        snapshot("01_Dashboard")

        // 2. Scroll down on Dashboard to show stats grid
        let dashboardScroll = app.scrollViews.firstMatch
        dashboardScroll.swipeUp()
        sleep(1)
        snapshot("02_Dashboard_Stats")

        // 3. Trends tab
        app.tabBars.buttons["Trends"].tap()
        sleep(2)
        snapshot("03_Trends")

        // 4. History tab
        app.tabBars.buttons["History"].tap()
        sleep(2)
        snapshot("04_History")

        // 5. Session tab — Start Session view
        app.tabBars.buttons["Session"].tap()
        sleep(1)
        snapshot("05_Start_Session")

        // 6. Navigate back to Dashboard, tap into Leak Finder
        app.tabBars.buttons["Dashboard"].tap()
        sleep(1)

        // Scroll to find Leak Finder
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<3 {
            let leakFinder = app.staticTexts["Leak Finder"]
            if leakFinder.exists {
                leakFinder.tap()
                sleep(2)
                snapshot("06_Leak_Finder")
                break
            }
            scrollView.swipeUp()
            sleep(1)
        }
    }
}
