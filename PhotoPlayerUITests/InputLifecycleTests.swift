import XCTest

final class InputLifecycleTests: XCTestCase {
    @MainActor func testFourToFiveAfterTabReturnWithMonitor() { checkSequence(monitor: true) }
    @MainActor func testSameSingleTapsWithMonitorDisabled() { checkSequence(monitor: false) }

    @MainActor
    private func checkSequence(monitor: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication.photoPlayerForTesting()
        app.launchArguments = ["--verify-diagnostic-copy"] + (monitor ? [] : ["--disable-input-monitor"])
        app.launch()
        XCTAssertTrue(app.buttons["videoCard.4"].waitForExistence(timeout: 20))
        for diagnostics in [false, true] {
            app.tabBars.buttons["Diagnostics"].tap()
            app.tabBars.buttons["Videos"].tap()
            if diagnostics { app.buttons["selectionDiagnostics"].tap() }
            // Cache both screen coordinates before opening 4; no additional
            // wait, element query, retry or second tap between Close and video 5.
            let targets = [4, 5].map { number in
                let card = app.buttons["videoCard.\(number)"]
                return (number, card.frame.midX, card.frame.minY + 55, card.value as! String)
            }
            for (number, x, y, dimensions) in targets {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).press(forDuration: 0.03)
                let selected = app.otherElements["selectedVideo"]
                XCTAssertTrue(selected.waitForExistence(timeout: 10))
                XCTAssertEqual(selected.label, diagnostics ? "Video \(number)" : "Playback")
                XCTAssertEqual(selected.value as? String, dimensions)
                ready(app)
                app.playerButton("closePlayer").tap()
            }
        }
        let report = copy(app)
        XCTAssertTrue(report.contains("lifecycle.tab.counter"))
        XCTAssertTrue(report.contains("lifecycle.tab.library"))
        XCTAssertTrue(report.contains("lifecycle.copy.snapshot"))
        XCTAssertTrue(report.contains("S4 V5"))
        XCTAssertTrue(report.contains("S4 V5 view.appear"))
        let value = app.staticTexts["selectionTrace.library"].value as! String
        XCTAssertEqual(value, "contacts=\(monitor ? 4 : 0);accepted=4;shown=4;requested=4;received=4;ready=4")
        XCTAssertEqual(report.contains("input.entry"), monitor)
        attach("input-lifecycle-monitor-\(monitor)")
    }

    @MainActor
    func testBackgroundStopsPlaybackAndInputContinuesAfterReturn() {
        continueAfterFailure = false
        let app = XCUIApplication.photoPlayerForTesting()
        app.launchArguments = ["--verify-diagnostic-copy"]
        app.launch()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 20))
        app.buttons["videoCard.1"].tap()
        ready(app)
        let state = app.buttons["playPause"]
        expect(state, "value == %@", "Playing")
        XCUIDevice.shared.press(.home)
        app.activate()
        expect(state, "value == %@", "Paused")
        app.playerButton("closePlayer").tap()
        let fifth = app.buttons["videoCard.5"]
        let dimensions = fifth.value as! String
        fifth.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.03)
        ready(app)
        XCTAssertEqual(app.otherElements["selectedVideo"].value as? String, dimensions)
        app.playerButton("closePlayer").tap()
        app.buttons["selectionDiagnostics"].tap()
        let report = copy(app)
        XCTAssertTrue(report.contains("lifecycle.scene.background"))
        XCTAssertTrue(report.contains("lifecycle.scene.active"))
        XCTAssertTrue(report.contains("S2 V5 view.appear"))
        XCTAssertTrue(report.contains("V5 contact.begin"))
        attach("input-after-background")
    }

    @MainActor private func ready(_ app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: app.buttons["playPause"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }
    @MainActor private func expect(_ element: XCUIElement, _ format: String, _ text: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }
    @MainActor private func copy(_ app: XCUIApplication) -> String {
        let button = app.buttons["copySelectionTrace.library"]
        button.tap()
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'lifecycle.copy.snapshot'"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
        return button.value as! String
    }
    @MainActor private func attach(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
