import XCTest

/// End-to-end scenarios on mock services (no network, no real purchases): a fresh install through
/// onboarding and the paywall, the core loop from Home to the journal, and account deletion.
/// Each screen on the way also runs Apple's accessibility audit.
final class DreamerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockServices", "-day", "-uiTesting"] + arguments
        app.launch()
        return app
    }

    /// Apple's audit, minus what the design deliberately does: fixed-size chrome text (tab bar,
    /// pills) and white text on the sky, which carries a shadow (checked by eye in IOS-10.2).
    @MainActor
    private func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .trait]) { issue in
            // Decorative sky and orb images carry no meaning.
            let ignored = issue.auditType == .hitRegion && issue.element?.elementType == .image
            if !ignored {
                print("AUDIT: \(issue.compactDescription) | \(issue.element?.elementType.rawValue ?? 0) '\(issue.element?.label ?? "")' \(issue.element?.frame ?? .zero)")
            }
            return ignored
        }
    }

    @MainActor
    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) not found")
        element.tap()
    }

    /// A leaving screen stays in the hierarchy while it animates out: tap the one on screen.
    @MainActor
    private func tapVisible(_ query: XCUIElementQuery, timeout: TimeInterval = 10) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            // Off-screen pages have no valid activation point, so isHittable would fail: the
            // centre of the frame on screen decides.
            let screen = XCUIApplication().windows.firstMatch.frame
            if let element = query.allElementsBoundByIndex.first(where: {
                $0.exists && !$0.frame.isEmpty && screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }) {
                element.tap()
                return
            }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
        XCTFail("No visible \(query)")
    }

    /// Scrolls up until the element can be tapped (it may sit under the tab bar).
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        var swipes = 0
        while !element.isHittable && swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    func testFreshInstallThroughOnboardingAndPaywall() throws {
        let app = launch(["-uiTestOpenEmailLink"])

        tapVisible(app.buttons.matching(identifier: "Get started"))
        tapVisible(app.buttons.matching(identifier: "Continue"))
        tapVisible(app.buttons.matching(identifier: "Get started"))
        try audit(app)
        tapVisible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "A dream keeps coming back")))
        tapVisible(app.buttons.matching(identifier: "Continue"))
        tapVisible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spiritual")))
        tapVisible(app.buttons.matching(identifier: "Continue"))

        // Account: the email link (opened by the mock a moment after it is "sent").
        let email = app.textFields["Your email"]
        tap(email)
        email.typeText("dreamer@example.com")
        tap(app.buttons["Continue with email"])

        // A new account meets the paywall; the mock store approves the purchase.
        tap(app.buttons["Try 7 days free"], timeout: 15)
        try audit(app)

        // Main: the reminder is offered once.
        tap(app.buttons["Not now"], timeout: 15)
        XCTAssertTrue(app.buttons["Record last night’s dream"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordToInterpretationAndJournal() throws {
        let app = launch(["-debugScreen", "home"])
        try audit(app)

        tap(app.buttons["Record last night’s dream"])
        let done = app.buttons["I’m done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        // The mock types the sample dream in; "I'm done" enables with the first words.
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: done)
        wait(for: [enabled], timeout: 10)
        done.tap()

        tap(app.buttons["Skip"])
        tap(app.buttons["See my interpretation"], timeout: 20)
        let overline = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Your interpretation")).firstMatch
        XCTAssertTrue(overline.waitForExistence(timeout: 5))
        try audit(app)

        let copy = app.buttons["Copy text"]
        scrollTo(copy, in: app)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)

        tap(app.buttons["Back"])
        tap(app.buttons["Journal"])
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        try audit(app)
    }

    /// The film opens edge to edge with Close and Share. `TEST_RUNNER_VIDEO_URL` (optional) gives it
    /// a real MP4 to play; without it the poster stands in.
    @MainActor
    func testTheDreamFilmPlaysFullScreen() throws {
        var arguments = ["-debugScreen", "interpretation", "-videoReady"]
        let videoURL = ProcessInfo.processInfo.environment["VIDEO_URL"]
        if let videoURL { arguments += ["-videoURL", videoURL] }
        let app = launch(arguments)

        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Watch your dream")).firstMatch)
        let film = app.otherElements["Your dream video"]
        XCTAssertTrue(film.waitForExistence(timeout: 5))
        XCTAssertEqual(film.frame.size, app.windows.firstMatch.frame.size, "the film fills the screen")
        XCTAssertTrue(app.buttons["videoShare"].exists)
        try audit(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if videoURL != nil {
            // The downloaded MP4 in the system sheet, which offers Save Video for a film.
            app.buttons["videoShare"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["Save Video"].waitForExistence(timeout: 15))
            add(XCTAttachment(screenshot: app.screenshot()))
            app.swipeDown(velocity: .fast)
            RunLoop.current.run(until: .now.addingTimeInterval(1))
        }

        tap(app.buttons["Close"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Watch your dream")).firstMatch
            .waitForExistence(timeout: 5))
    }

    /// The export (mock data) opens the system sheet with the JSON file, and closing it leaves Settings.
    @MainActor
    func testExportingDataOpensTheShareSheet() throws {
        let app = launch(["-debugScreen", "settings"])
        let export = app.buttons["Export my data"]
        scrollTo(export, in: app)
        export.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Save to Files"].waitForExistence(timeout: 10))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(export.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeletingTheAccountStartsOver() throws {
        let app = launch(["-debugScreen", "settings"])
        try audit(app)

        let delete = app.buttons["Delete account and all dreams"]
        scrollTo(delete, in: app)
        delete.tap()
        // The confirmation sheet has the same destructive button, over the one in Settings.
        tapVisible(app.buttons.matching(identifier: "Delete account and all dreams"))
        XCTAssertTrue(app.buttons.matching(identifier: "Get started").firstMatch.waitForExistence(timeout: 10))
    }
}
