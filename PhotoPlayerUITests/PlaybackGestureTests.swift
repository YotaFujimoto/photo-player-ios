import XCTest
import UIKit

final class PlaybackGestureTests: XCTestCase {
    @MainActor
    private func open(details: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.photoPlayerForTesting()
        app.launchArguments = ["--playback-diagnostics"] + (details ? ["--player-detail-mode"] : [])
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'videoCard.' AND value == '320x180'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["buildNumber"].exists)
        XCTAssertFalse(app.staticTexts["selectionTrace.library"].exists)
        XCTAssertFalse(card.label.contains("Video 1"))
        card.tap()
        state(app, "Playing")
        XCTAssertEqual(app.staticTexts["selectionTrace.player"].exists, details)
        XCTAssertFalse(app.staticTexts["actualRate"].exists)
        return app
    }

    @MainActor
    func testDoubleTapBoundsSingleTapAndControlsInBothOrientations() {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.playerButton("playPause").tap()
        state(app, "Paused")
        setRate(app, "0.25×")
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let surface = app.otherElements["videoSurface"]
            XCTAssertTrue(surface.isHittable)
            app.descendants(matching: .any)["seekSlider"].coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
            // Reach the exact boundary before testing another skip there.
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            position(app, ["0:00"])
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            position(app, ["0:00"])
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
            // Wait for this deliberate single tap's visibility change before
            // the position helper reveals controls; event synthesis can return
            // while UIKit is still excluding a possible second tap.
            expect(app.buttons["playPause"], "exists == false")
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
            XCTAssertEqual(app.playerButton("rateMenu").value as? String, "0.25×")
            XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
            app.playerButton("playPause").tap()
            state(app, "Playing")
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
            state(app, "Playing")
            XCTAssertEqual(app.playerButton("rateMenu").value as? String, "0.25×")
            app.playerButton("playPause").tap()
            state(app, "Paused")
            let seconds = readPosition(app)
            XCTAssertGreaterThanOrEqual(seconds, 10)
            XCTAssertLessThan(seconds, 15)
            attach("gesture-skip-\(orientation.rawValue)")
        }
        app.playerButton("closePlayer").tap()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHeldDoubleSpeedRestoresRateAndNeverStartsPausedPlayback() {
        let app = open(details: true)
        defer { XCUIDevice.shared.orientation = .portrait }
        app.playerButton("playPause").tap()
        state(app, "Paused")
        // Paused holding must preserve the exact displayed position. It does not
        // depend on XCTest's approximate slider gesture landing at zero.
        let stoppedPosition = app.staticTexts["playbackPosition"].label
        setRate(app, "0.25×")
        let surface = app.otherElements["videoSurface"]
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 2)
        position(app, [stoppedPosition])
        state(app, "Paused")
        app.playerButton("playPause").tap()
        state(app, "Playing")
        // At 0.25× the ordinary wall time cannot account for this advance.
        // This checks the real PhotoKit AVPlayer during a physical held gesture.
        verifyHeldAdvance(app, surface: surface)
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        XCTAssertEqual(app.playerButton("rateMenu").value as? String, "0.25×")
        state(app, "Playing")
        app.buttons["Playback details"].tap()
        expect(app.staticTexts["actualRate"], "label CONTAINS '0.25'")
        attach("gesture-hold-restored")
        XCUIDevice.shared.orientation = .landscapeLeft
        verifyHeldAdvance(app, surface: surface)
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        XCTAssertEqual(app.playerButton("rateMenu").value as? String, "0.25×")
        attach("gesture-hold-landscape")
        // In fullscreen the close control overlays the canvas. Use portrait
        // for the original leave-video-bounds cancellation check.
        XCUIDevice.shared.orientation = .portrait
        let source = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let outside = app.playerButton("closePlayer").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(forDuration: 0.8, thenDragTo: outside, withVelocity: .fast, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.playerButton("closePlayer").exists)
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        XCTAssertEqual(app.playerButton("rateMenu").value as? String, "0.25×")
        XCUIDevice.shared.press(.home)
        app.activate()
        state(app, "Paused")
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
        app.playerButton("closePlayer").tap()
        app.buttons["videoCard.1"].tap()
        state(app, "Playing")
        XCTAssertEqual(app.playerButton("rateMenu").value as? String, "1×")
        XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
    }

    @MainActor private func setRate(_ app: XCUIApplication, _ rate: String) {
        app.playerButton("rateMenu").tap(); app.buttons[rate].tap()
    }
    @MainActor private func verifyHeldAdvance(_ app: XCUIApplication, surface: XCUIElement) {
        app.revealPlayerControls()
        let start = readPosition(app)
        let started = ProcessInfo.processInfo.systemUptime
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 3)
        let advanced = readPosition(app) - start
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let extra = Double(advanced) - elapsed * 0.25
        XCTAssertGreaterThan(extra, 2.5, "A held press must temporarily accelerate the real player")
        XCTAssertLessThan(extra, 6.5, "Releasing a hold must not also trigger a 10-second skip")
    }
    @MainActor private func state(_ app: XCUIApplication, _ state: String) {
        expect(app.otherElements["videoSurface"], "value == '\(state)'")
    }
    @MainActor private func position(_ app: XCUIApplication, _ labels: [String]) {
        app.revealPlayerControls()
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label IN %@", labels), object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }
    @MainActor private func readPosition(_ app: XCUIApplication) -> Int {
        app.revealPlayerControls()
        return app.staticTexts["playbackPosition"].label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
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
