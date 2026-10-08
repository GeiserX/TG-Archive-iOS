import XCTest

/// The demo's `family` viewer: three chats, downloads on.
final class ViewerTests: DemoTestCase {
    /// Opens every chat the viewer sees, reads each back to its first message, then opens a photo.
    func testViewerReadsEveryChatToTheTopAndOpensAPhoto() throws {
        try launchSignedOut()
        signIn(username: Demo.viewerUsername, password: Demo.viewerPassword)

        let rows = elements(prefixed: "chat.row.")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        let chats = identifiers(prefixed: "chat.row.")
        XCTAssertEqual(chats.count, 3, "the demo's family viewer sees three chats: \(chats)")
        for chat in chats {
            element(chat).tap()
            scrollThreadToTop()
            goBack()
            XCTAssertTrue(element(chat).waitForExistence(timeout: 10))
        }

        openChat(titled: "Weekend Hikers")
        let photos = app.buttons.matching(NSPredicate(format: "label == 'Photo'"))
        XCTAssertTrue(scrollThread(downUntil: photos.firstMatch), "no photo near the end of Weekend Hikers")
        try XCTUnwrap(firstHittable(photos), "no photo on screen").tap()
        XCTAssertTrue(element("media.viewer.photo").waitForExistence(timeout: 20), "the photo did not open")
        element("media.viewer.done").tap()
        XCTAssertFalse(element("media.viewer.done").waitForExistence(timeout: 2))
    }

    /// Searches every chat, opens a hit, and finds the thread opened at that message.
    func testViewerSearchOpensTheChatAtTheHit() throws {
        try launchSignedOut()
        signIn(username: Demo.viewerUsername, password: Demo.viewerPassword)

        tabBar.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("trailhead")

        let hits = elements(prefixed: "search.row.")
        XCTAssertTrue(hits.firstMatch.waitForExistence(timeout: 20), "no hit for trailhead")
        let hit = hits.firstMatch
        XCTAssertTrue(hit.label.localizedCaseInsensitiveContains("trailhead"), hit.label)
        // search.row.<chat ref>.<message id>; a ref never holds a dot.
        let messageID = try XCTUnwrap(hit.identifier.split(separator: ".").last)
        hit.tap()

        let anchor = element("message.\(messageID)")
        XCTAssertTrue(anchor.waitForExistence(timeout: 20), "the thread did not open at message \(messageID)")
        XCTAssertTrue(anchor.isHittable, "message \(messageID) is not on screen")
    }

    /// A wrong password is refused with the 401 sentence, and the sign-in check this suite relies on fails:
    /// proof that a broken sign-in turns the other tests red.
    func testWrongPasswordIsRefused() throws {
        try launchSignedOut()
        continueAfterFailure = true
        // Only the sign-in check's own failure is expected; anything else, a lost tap included, still fails.
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("not signed in") }
        XCTExpectFailure("a wrong password must fail the sign-in check", options: options) {
            signIn(username: Demo.viewerUsername, password: "not-the-demo-password")
        }
        let banner = element("banner.message")
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertEqual(banner.label, "Wrong username or password.")
        XCTAssertFalse(tabBar.exists)
        XCTAssertTrue(app.buttons["signin.submit"].exists)
    }
}
