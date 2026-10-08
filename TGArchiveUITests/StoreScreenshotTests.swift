import XCTest

/// The App Store screenshots, from the demo's invented archive only. They need a 6.9-inch iPhone (1320 x 2868
/// pixels). With `TGARCHIVE_SCREENSHOT_DIR` set the PNGs are written there and another screen size fails;
/// without it the test skips on other screens and keeps the shots as attachments in the result bundle.
final class StoreScreenshotTests: DemoTestCase {
    static let storeSize = CGSize(width: 1320, height: 2868)

    private var directory: URL?
    private var index = 0

    func testStoreScreenshots() throws {
        try launchSignedOut()
        let size = Self.pixelSize(XCUIScreen.main.screenshot())
        directory = Demo.env("TGARCHIVE_SCREENSHOT_DIR").map { URL(fileURLWithPath: $0, isDirectory: true) }
        if size != Self.storeSize {
            if directory != nil {
                XCTFail("store screenshots need a 6.9-inch iPhone (1320 x 2868 px), this one is \(size)")
            }
            throw XCTSkip("store screenshots need a 6.9-inch iPhone (1320 x 2868 px), this one is \(size)")
        }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        signIn(username: Demo.masterUsername, password: Demo.masterPassword)

        // The chat list, with its avatars loaded.
        XCTAssertTrue(elements(prefixed: "chat.row.").firstMatch.waitForExistence(timeout: 20))
        settle()
        shoot("chats")

        // A thread with a poll, a voice note and its transcript. The nearest photo is two stickers further on,
        // below the screen, so it gets its own shot in the viewer.
        openChat(titled: "Weekend Hikers")
        let poll = elements(containing: "Where should we go next Sunday?").firstMatch
        XCTAssertTrue(scrollThread(downUntil: poll), "no poll in Weekend Hikers")
        settle()
        shoot("thread")
        let photos = app.buttons.matching(NSPredicate(format: "label == 'Photo'"))
        for _ in 0..<4 where firstHittable(photos) == nil {
            app.scrollViews.firstMatch.swipeUp()
        }
        let photo = try XCTUnwrap(firstHittable(photos), "no photo after the poll")

        // The photo, full screen.
        photo.tap()
        XCTAssertTrue(element("media.viewer.photo").waitForExistence(timeout: 20))
        settle()
        shoot("photo")
        element("media.viewer.done").tap()
        goBack()

        // A venue card in a private chat.
        openChat(titled: "Juniper")
        let venue = elements(containing: "Elm Street Bakery").firstMatch
        XCTAssertTrue(scrollThread(downUntil: venue), "no venue in Juniper")
        // Bring the card to the upper third, so the location and live location under it show too. Hold at the end
        // of the drag so the thread does not fling on.
        let screen = app.frame
        let shift = min(max((venue.frame.minY - screen.minY) / screen.height - 0.22, -0.4), 0.4)
        if abs(shift) > 0.05 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + shift / 2))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - shift / 2))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        XCTAssertTrue(venue.isHittable, "the venue card left the screen")
        settle()
        shoot("location")
        goBack()

        // Search results across every chat.
        tabBar.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("trail\n")
        XCTAssertTrue(elements(prefixed: "search.row.").firstMatch.waitForExistence(timeout: 20))
        settle()
        shoot("search")
    }

    /// Lets thumbnails and avatars arrive and animations end.
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }

    private func shoot(_ name: String) {
        index += 1
        let fileName = String(format: "%02d-%@", index, name)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory else { return }
        let url = directory.appendingPathComponent("\(fileName).png")
        XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: url), "could not write \(url.path)")
    }

    static func pixelSize(_ screenshot: XCUIScreenshot) -> CGSize {
        let image = screenshot.image
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
}
