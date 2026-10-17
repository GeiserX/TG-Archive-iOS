import XCTest

/// "Try the demo" on the connect screen opens the archive bundled in the app, with no server: this test runs
/// with or without the demo server.
final class DemoModeTests: DemoTestCase {
    func testDemoOpensReadsSearchesAndExits() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        self.app = app
        app.launch()
        app.signOutIfSignedIn()
        if element("signin.changeServer").waitForExistence(timeout: 2) {
            element("signin.changeServer").tap()
        }

        let demo = app.buttons["connect.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "no Try the Demo button")
        for _ in 0..<4 where !demo.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        demo.tap()
        XCTAssertTrue(element("demo.banner").waitForExistence(timeout: 10), "the demo is not labelled")

        // A thread, and one of its bundled photos in the viewer.
        openChat(titled: "Weekend Hikers")
        let photos = app.buttons.matching(NSPredicate(format: "label == 'Photo'"))
        for _ in 0..<8 where firstHittable(photos) == nil {
            app.scrollViews.firstMatch.swipeDown()
        }
        let photo = try XCTUnwrap(firstHittable(photos), "no photo in the demo's Weekend Hikers")
        photo.tap()
        XCTAssertTrue(element("media.viewer.photo").waitForExistence(timeout: 10), "the demo photo did not open")
        element("media.viewer.done").tap()
        goBack()

        // Search across the demo, and open a hit in its chat.
        tabBar.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("trail\n")
        let hit = elements(prefixed: "search.row.").firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10), "the demo search found nothing")
        hit.tap()
        XCTAssertTrue(elements(prefixed: "message.").firstMatch.waitForExistence(timeout: 10), "the hit did not open")

        // Out again, to the connect screen; a relaunch does not bring the demo back.
        element("demo.exit").tap()
        XCTAssertTrue(element("connect.address").waitForExistence(timeout: 10), "Exit Demo did not return to connect")
        app.terminate()
        app.launch()
        XCTAssertTrue(element("connect.address").waitForExistence(timeout: 10), "the demo came back after a relaunch")
        XCTAssertFalse(element("demo.banner").exists)
    }
}
