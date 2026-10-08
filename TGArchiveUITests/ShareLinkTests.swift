import XCTest

/// The demo's share link: one chat, downloads off.
final class ShareLinkTests: DemoTestCase {
    func testShareLinkReadsItsChatWithDownloadsOff() throws {
        try launchSignedOut()
        signIn(token: Demo.shareToken)

        let rows = elements(prefixed: "chat.row.")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        let chats = identifiers(prefixed: "chat.row.")
        XCTAssertEqual(chats.count, 1, "the demo's share link opens one chat: \(chats)")
        XCTAssertTrue(rows.firstMatch.label.contains("Weekend Hikers"), rows.firstMatch.label)

        openChat(titled: "Weekend Hikers")
        let tile = elements(containing: "Downloads are off for this login").firstMatch
        XCTAssertTrue(scrollThread(downUntil: tile), "no downloads-off tile in Weekend Hikers")
        // The thread holds photos, and none of them is offered: no thumbnail is ever asked for.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Photo'")).firstMatch.exists)
        goBack()

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(element("settings.noDownload").waitForExistence(timeout: 10))
        XCTAssertTrue(element("settings.signedInAs").label.contains("Hike photos"),
                      element("settings.signedInAs").label)
    }
}
