import XCTest

/// The demo server the UI tests read (scripts/demo-server.sh). The logins are the public demo constants of the
/// server project's generator, and each can be overridden from the environment.
enum Demo {
    static var url: String? { env("TGARCHIVE_DEMO_URL") }
    static var masterUsername: String { env("TGARCHIVE_DEMO_USERNAME") ?? "admin" }
    static var masterPassword: String { env("TGARCHIVE_DEMO_PASSWORD") ?? "demo-admin-not-a-secret" }
    static let viewerUsername = "family"
    static var viewerPassword: String { env("TGARCHIVE_DEMO_VIEWER_PASSWORD") ?? "demo-viewer-not-a-secret" }
    static var shareToken: String { env("TGARCHIVE_DEMO_SHARE_TOKEN") ?? "demo-share-link-not-a-secret" }

    static func env(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name] ?? ""
        return value.isEmpty ? nil : value
    }
}

/// A UI test against the live demo server. Each test starts signed out and ends signed out, so it never leaves
/// a server session behind (each user holds at most ten). Every test signs in once at most: sign-in and
/// share-link sign-in share a limit of 15 attempts per client IP in 5 minutes.
@MainActor
class DemoTestCase: XCTestCase {
    var app: XCUIApplication!
    var demoURL = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app signed out against the demo, and signs out again when the test ends, however it ends.
    /// Called first by every test; it skips the test when no demo server is set.
    func launchSignedOut() throws {
        guard let url = Demo.url else {
            throw XCTSkip("TGARCHIVE_DEMO_URL is not set; start the demo with scripts/demo-server.sh")
        }
        demoURL = url
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        self.app = app
        addTeardownBlock { @MainActor in
            // A fresh launch leaves whatever screen a failure stopped on, then the session is ended.
            app.launch()
            app.signOutIfSignedIn()
        }
        app.launch()
        app.signOutIfSignedIn()
    }

    // MARK: Elements

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func elements(prefixed prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    func elements(containing text: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
    }

    var tabBar: XCUIElement { app.tabBars.firstMatch }

    /// Waits until one of the elements exists and returns it.
    @discardableResult
    func waitForAny(_ candidates: [XCUIElement], timeout: TimeInterval = 20,
                    file: StaticString = #filePath, line: UInt = #line) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = candidates.first(where: { $0.exists }) { return found }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        XCTFail("none of \(candidates.map(\.description)) appeared within \(Int(timeout)) s", file: file, line: line)
        return nil
    }

    /// The ids of the elements whose identifier starts with `prefix`, in screen order, without repeats.
    func identifiers(prefixed prefix: String) -> [String] {
        var seen = Set<String>()
        return elements(prefixed: prefix).allElementsBoundByIndex
            .map { $0.identifier }
            .filter { seen.insert($0).inserted }
    }

    // MARK: Session

    /// Connects to the demo server and opens its sign-in screen.
    func openSignIn(file: StaticString = #filePath, line: UInt = #line) {
        waitForAny([element("connect.address"), element("signin.submit")], file: file, line: line)
        if element("signin.changeServer").exists {
            element("signin.changeServer").tap()
        }
        let address = app.textFields["connect.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10), file: file, line: line)
        replaceText(in: address, with: demoURL)
        app.buttons["connect.continue"].tap()
        XCTAssertTrue(element("signin.submit").waitForExistence(timeout: 20), "the demo server did not answer",
                      file: file, line: line)
        XCTAssertEqual(element("signin.server").label, URL(string: demoURL)?.host(), file: file, line: line)
    }

    /// Signs in with a username and password and fails unless the archive opens.
    func signIn(username: String, password: String, file: StaticString = #filePath, line: UInt = #line) {
        openSignIn(file: file, line: line)
        app.segmentedControls.buttons["Account"].tap()
        replaceText(in: app.textFields["signin.username"], with: username)
        replaceText(in: app.secureTextFields["signin.password"], with: password)
        submitSignIn(file: file, line: line)
    }

    /// Signs in with a share link and fails unless the archive opens.
    func signIn(token: String, file: StaticString = #filePath, line: UInt = #line) {
        openSignIn(file: file, line: line)
        app.segmentedControls.buttons["Share link"].tap()
        let field = app.textViews["signin.token"].exists ? app.textViews["signin.token"] : app.textFields["signin.token"]
        replaceText(in: field, with: token)
        submitSignIn(file: file, line: line)
    }

    private func submitSignIn(file: StaticString, line: UInt) {
        let submit = app.buttons["signin.submit"]
        XCTAssertTrue(submit.isEnabled, "the sign-in button is disabled", file: file, line: line)
        submit.tap()
        let banner = element("banner.message")
        waitForAny([tabBar, banner], file: file, line: line)
        XCTAssertTrue(tabBar.exists, "not signed in: \(banner.exists ? banner.label : "no tab bar")",
                      file: file, line: line)
    }

    // MARK: Input and scrolling

    /// Clears a text field and types `text` into it.
    func replaceText(in field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field \(field)", file: file, line: line)
        // Tap after the last character, so the deletes below clear everything. A tap made while the screen is
        // still settling can be lost, so tap until the field has the keyboard focus.
        for _ in 0..<5 where !hasFocus(field) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            _ = field.waitForExistence(timeout: 0.5)
        }
        XCTAssertTrue(hasFocus(field), "\(field) never took the keyboard focus", file: file, line: line)
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    private func hasFocus(_ field: XCUIElement) -> Bool {
        field.value(forKey: "hasKeyboardFocus") as? Bool ?? false
    }

    /// Swipes down (towards older messages) until `target` is on screen.
    @discardableResult
    func scrollThread(downUntil target: XCUIElement, attempts: Int = 20) -> Bool {
        var left = attempts
        while !(target.exists && target.isHittable) && left > 0 {
            app.scrollViews.firstMatch.swipeDown()
            left -= 1
        }
        return target.exists && target.isHittable
    }

    /// Scrolls an open thread up until the oldest message stays first: no older page comes any more.
    func scrollThreadToTop(file: StaticString = #filePath, line: UInt = #line) {
        let messages = elements(prefixed: "message.")
        XCTAssertTrue(messages.firstMatch.waitForExistence(timeout: 20), "the thread shows no message",
                      file: file, line: line)
        var top = messages.firstMatch.identifier
        var unchanged = 0
        for _ in 0..<60 {
            app.scrollViews.firstMatch.swipeDown(velocity: .fast)
            let now = messages.firstMatch.identifier
            unchanged = now == top ? unchanged + 1 : 0
            top = now
            if unchanged == 2 {
                XCTAssertFalse(element("banner.message").exists,
                               "an older page failed: \(element("banner.message").label)", file: file, line: line)
                return
            }
        }
        XCTFail("the thread never reached its first message", file: file, line: line)
    }

    /// Opens the chat whose row shows `title`.
    func openChat(titled title: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = elements(prefixed: "chat.row.").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no chat \(title)", file: file, line: line)
        row.tap()
        XCTAssertTrue(elements(prefixed: "message.").firstMatch.waitForExistence(timeout: 20),
                      "\(title) shows no message", file: file, line: line)
    }

    func goBack() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    /// The first element of `query` that is on screen.
    func firstHittable(_ query: XCUIElementQuery) -> XCUIElement? {
        query.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
    }
}

extension XCUIApplication {
    /// Ends the session when the app opened signed in, and returns whether it did. The app is then on the
    /// sign-in screen; a fresh launch shows the connect screen.
    @discardableResult
    func signOutIfSignedIn(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let tabBar = tabBars.firstMatch
        let deadline = Date().addingTimeInterval(20)
        let screens = [tabBar, descendants(matching: .any)["connect.address"].firstMatch,
                       descendants(matching: .any)["signin.submit"].firstMatch]
        while !screens.contains(where: { $0.exists }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(screens.contains(where: { $0.exists }), "the app shows no known screen", file: file, line: line)
        guard tabBar.exists else { return false }
        // Settings is the third tab; by position, since a launch without the English arguments may be in Spanish.
        tabBar.buttons.element(boundBy: 2).tap()
        let signOut = descendants(matching: .any)["settings.signOut"].firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<8 where !signOut.isHittable {
            collectionViews.firstMatch.swipeUp()
        }
        // The floating tab bar can cover the middle of the row: tap its leading end.
        signOut.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.4)).tap()
        let confirm = buttons.matching(identifier: "settings.signOut.confirm").firstMatch
        if !confirm.waitForExistence(timeout: 10) {
            XCTFail("no sign-out confirmation", file: file, line: line)
        }
        confirm.tap()
        XCTAssertTrue(descendants(matching: .any)["signin.submit"].firstMatch.waitForExistence(timeout: 20),
                      "sign-out did not finish", file: file, line: line)
        return true
    }
}
