import XCTest

final class CounterPersistenceTests: XCTestCase {
    @MainActor
    func testCounterSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let counter = app.staticTexts["counterValue"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        let initialValue = try XCTUnwrap(Int(counter.label))
        let build = app.staticTexts["buildNumber"]
        XCTAssertTrue(build.label.range(of: #"^ビルド [0-9]+$"#, options: .regularExpression) != nil)
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
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.terminate()
        app.launch()
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
