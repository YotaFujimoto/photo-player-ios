import XCTest

final class CounterPersistenceTests: XCTestCase {
    @MainActor
    func testCounterSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication.photoPlayerForTesting()
        app.launch()
        app.tabBars.buttons["Diagnostics"].tap()

        let counter = app.staticTexts["counterValue"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        let initialValue = try XCTUnwrap(Int(counter.label))
        let build = app.staticTexts["buildNumber"]
        XCTAssertTrue(build.label.range(of: #"^Build [0-9]+$"#, options: .regularExpression) != nil)
        let originalBuild = build.label

        for _ in 0..<12 {
            app.buttons["incrementButton"].tap()
        }
        let expectedValue = String(initialValue + 12)
        let savedValue = NSPredicate(format: "label == %@", expectedValue)
        expectation(for: savedValue, evaluatedWith: counter)
        waitForExpectations(timeout: 5)
        attachScreenshot(name: "counter-portrait")

        // Use a normal background transition before terminating the process.
        XCUIDevice.shared.press(.home)
        // CI 43689265348 showed Home onscreen while XCUIApplication.state still
        // reported foreground. Observe the actual Home icon before terminating;
        // persistence still requires a real process exit and a new launch.
        let homeIcon = XCUIApplication(bundleIdentifier: "com.apple.springboard").icons["PhotoPlayer"]
        let backgrounded = liveUIExpectation(predicate: NSPredicate(format: "hittable == YES"), object: homeIcon)
        XCTAssertEqual(
            XCTWaiter.wait(for: [backgrounded], timeout: 10), .completed,
            "Home must be visible before relaunch; state=\(app.state.rawValue)"
        )
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        app.tabBars.buttons["Diagnostics"].tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, expectedValue)
        XCTAssertEqual(build.label, originalBuild)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["incrementButton"].isHittable)
        XCTAssertEqual(counter.label, expectedValue)
        attachScreenshot(name: "counter-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
