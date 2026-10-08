import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTitle() throws {
        let app = XCUIApplication()
        app.launch()
        // A session an earlier UI test run left behind opens the archive: end it, and relaunch to connect afresh.
        if app.signOutIfSignedIn() {
            app.launch()
        }
        let title = app.staticTexts["root.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "TG Archive")
    }
}
