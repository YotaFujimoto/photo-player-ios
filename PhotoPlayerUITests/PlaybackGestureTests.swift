import XCTest
import UIKit

final class PlaybackGestureTests: XCTestCase {
    @MainActor
    private func open() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--playback-diagnostics"]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'videoCard.' AND value == '320x180'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["buildNumber"].exists)
        XCTAssertFalse(app.staticTexts["selectionTrace.library"].exists)
        XCTAssertFalse(card.label.contains("Video 1"))
        card.tap()
        state(app, "Playing")
        XCTAssertFalse(app.staticTexts["selectionTrace.player"].exists)
        XCTAssertFalse(app.staticTexts["actualRate"].exists)
        return app
    }

    @MainActor
    func testDoubleTapBoundsSingleTapAndControlsInBothOrientations() {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["playPause"].tap()
        state(app, "Paused")
        setRate(app, "0.25×")
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let surface = app.otherElements["videoSurface"]
            XCTAssertTrue(surface.isHittable)
            app.sliders["seekSlider"].adjust(toNormalizedSliderPosition: 0)
            // Slider adjustment is approximate; the explicit backward skip
            // reaches the boundary before testing another skip at that boundary.
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            position(app, ["0:00"])
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            position(app, ["0:00"])
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
            position(app, ["0:00"])
            let right = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
            right.doubleTap()
            position(app, ["0:10"])
            right.doubleTap()
            position(app, ["0:20"])
            right.doubleTap()
            position(app, ["0:30"])
            right.doubleTap()
            position(app, ["0:30"])
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            position(app, ["0:20"])
            state(app, "Paused")
            XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
            XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
            app.buttons["playPause"].tap()
            state(app, "Playing")
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            state(app, "Playing")
            XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
            app.buttons["playPause"].tap()
            state(app, "Paused")
            let seconds = readPosition(app)
            XCTAssertGreaterThanOrEqual(seconds, 10)
            XCTAssertLessThan(seconds, 15)
            attach("gesture-skip-\(orientation.rawValue)")
        }
        app.buttons["closePlayer"].tap()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHeldDoubleSpeedRestoresRateAndNeverStartsPausedPlayback() {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["playPause"].tap()
        state(app, "Paused")
        // Paused holding must preserve the exact displayed position. It does not
        // depend on XCTest's approximate slider gesture landing at zero.
        let stoppedPosition = app.staticTexts["playbackPosition"].label
        setRate(app, "0.25×")
        let surface = app.otherElements["videoSurface"]
        surface.press(forDuration: 2)
        position(app, [stoppedPosition])
        state(app, "Paused")
        app.buttons["playPause"].tap()
        state(app, "Playing")
        // At 0.25× the ordinary wall time cannot account for this advance.
        // This checks the real PhotoKit AVPlayer during a physical held gesture.
        verifyHeldAdvance(app, surface: surface)
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
        state(app, "Playing")
        app.buttons["playerDiagnostics"].tap()
        app.buttons["Playback details"].tap()
        expect(app.staticTexts["actualRate"], "label CONTAINS '0.25'")
        attach("gesture-hold-restored")
        app.buttons["playerDiagnostics"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        verifyHeldAdvance(app, surface: surface)
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
        attach("gesture-hold-landscape")
        // Leave the video region during a hold; no seek or control action occurs.
        let source = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let outside = app.buttons["closePlayer"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(forDuration: 0.8, thenDragTo: outside, withVelocity: .fast, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["closePlayer"].exists)
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
        XCUIDevice.shared.press(.home)
        app.activate()
        state(app, "Paused")
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        app.buttons["closePlayer"].tap()
        app.buttons["videoCard.1"].tap()
        state(app, "Playing")
        XCTAssertEqual(app.buttons["rateMenu"].value as? String, "1×")
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
    }

    @MainActor private func setRate(_ app: XCUIApplication, _ rate: String) {
        app.buttons["rateMenu"].tap(); app.buttons[rate].tap()
    }
    @MainActor private func verifyHeldAdvance(_ app: XCUIApplication, surface: XCUIElement) {
        let start = readPosition(app)
        let started = ProcessInfo.processInfo.systemUptime
        surface.press(forDuration: 3)
        let advanced = readPosition(app) - start
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let extra = Double(advanced) - elapsed * 0.25
        XCTAssertGreaterThan(extra, 2.5, "A held press must temporarily accelerate the real player")
        XCTAssertLessThan(extra, 6.5, "Releasing a hold must not also trigger a 10-second skip")
    }
    @MainActor private func state(_ app: XCUIApplication, _ state: String) {
        expect(app.buttons["playPause"], "value == '\(state)'")
    }
    @MainActor private func position(_ app: XCUIApplication, _ labels: [String]) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label IN %@", labels), object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }
    @MainActor private func readPosition(_ app: XCUIApplication) -> Int {
        app.staticTexts["playbackPosition"].label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
    @MainActor private func expect(_ element: XCUIElement, _ format: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }
    @MainActor private func attach(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
