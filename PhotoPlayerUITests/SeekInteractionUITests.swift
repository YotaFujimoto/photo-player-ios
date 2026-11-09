import XCTest
import UIKit

final class SeekInteractionUITests: XCTestCase {
    @MainActor private func open(held: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--playback-diagnostics"] + (held ? ["--hold-player-result"] : [])
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'videoCard.' AND value == '320x180'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        if !held { state(app, "Playing"); app.buttons["playPause"].tap(); state(app, "Paused") }
        return app
    }
    @MainActor private func bar(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["seekSlider"] }
    @MainActor private func setPosition(_ app: XCUIApplication, fraction: CGFloat, y: CGFloat = 0.5) {
        bar(app).coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: y)).tap()
    }
    @MainActor private func state(_ app: XCUIApplication, _ value: String) {
        expect(app.buttons["playPause"], NSPredicate(format: "value == %@", value))
    }
    @MainActor private func expect(_ element: XCUIElement, _ predicate: NSPredicate) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
    }
    @MainActor private func position(_ app: XCUIApplication, near seconds: Int, tolerance: Int = 1) {
        expect(app.staticTexts["playbackPosition"], NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement else { return false }
            let value = element.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
            return abs(value - seconds) <= tolerance
        })
    }
    @MainActor private func readPosition(_ app: XCUIApplication) -> Int {
        app.staticTexts["playbackPosition"].label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
    @MainActor private func setSlow(_ app: XCUIApplication) {
        app.buttons["rateMenu"].tap(); app.buttons["0.25×"].tap()
    }
    @MainActor private func drag(_ surface: XCUIElement, from x: CGFloat, to target: CGFloat, y: CGFloat = 0.5, endY: CGFloat = 0.5, hold: TimeInterval = 0.05, endHold: TimeInterval = 0) {
        surface.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).press(forDuration: hold,
            thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: target, dy: endY)),
            withVelocity: .slow, thenHoldForDuration: endHold)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testBarTapDragHitAreaAndPlaybackIntentInBothOrientations() {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        setSlow(app)
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertGreaterThanOrEqual(bar(app).frame.height, 44)
            setPosition(app, fraction: 0.25, y: 0.05); position(app, near: 7)
            setPosition(app, fraction: 0.75, y: 0.95); position(app, near: 22)
            drag(bar(app), from: 0.2, to: 0.5); position(app, near: 15)
            state(app, "Paused")
            XCTAssertFalse(app.staticTexts["skipFeedback"].exists)
            XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
            XCTAssertFalse(app.otherElements["seekPreview"].exists)
            app.buttons["playPause"].tap(); state(app, "Playing")
            setPosition(app, fraction: 0.25); state(app, "Playing")
            XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
            app.buttons["playPause"].tap(); state(app, "Paused")
            position(app, near: 8, tolerance: 2)
            // Continuous tracking beyond the edge reaches the exact endpoints.
            drag(bar(app), from: 0.5, to: 1.02); position(app, near: 30, tolerance: 0)
            drag(bar(app), from: 0.5, to: -0.02); position(app, near: 0, tolerance: 0)
            capture("bar-tap-drag-\(orientation.rawValue)")
        }
    }

    @MainActor func testLoadingErrorAndSeekOverlaysNeverMoveNormalControls() {
        let app = open(held: true)
        let release = app.buttons["releasePlayerResult"]
        XCTAssertTrue(release.waitForExistence(timeout: 20))
        let elements = [app.otherElements["videoSurface"], bar(app), app.buttons["playPause"], app.buttons["rateMenu"]]
        let frames = elements.map(\.frame)
        app.buttons["cancelDownload"].tap()
        XCTAssertTrue(app.buttons["retryVideo"].waitForExistence(timeout: 10))
        assertFrames(elements, frames)
        app.buttons["retryVideo"].tap()
        expect(release, NSPredicate(format: "enabled == true"))
        assertFrames(elements, frames)
        capture("loading-overlay-fixed-layout")
        release.tap(); state(app, "Playing")
        assertFrames(elements, frames)
        app.buttons["playPause"].tap(); state(app, "Paused")
        setPosition(app, fraction: 0.5); position(app, near: 15)
        assertFrames(elements, frames)
        XCTAssertFalse(app.staticTexts["Buffering…"].exists)
        XCTAssertFalse(app.staticTexts["Buffering..."].exists)
        XCTAssertFalse(app.staticTexts["playerState"].exists)
        capture("normal-seek-fixed-layout")
    }

    @MainActor func testSkipFeedbackIsBoundedReplacedAndDoesNotBlockInput() {
        let app = open()
        let surface = app.otherElements["videoSurface"]
        setPosition(app, fraction: 0.5); position(app, near: 15)
        let frame = surface.frame
        let right = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        right.doubleTap()
        let feedback = app.staticTexts["skipFeedback"]
        // waitForExistence's first poll was 1.05s after the gesture in CI,
        // after this deliberately one-second HUD had already expired. Query
        // immediately after event synthesis instead of waiting a polling cycle.
        XCTAssertTrue(feedback.exists)
        XCTAssertTrue(feedback.label.contains("+10s"))
        capture("skip-feedback-forward")
        position(app, near: 25)
        right.doubleTap(); position(app, near: 30, tolerance: 0)
        right.doubleTap()
        XCTAssertTrue(feedback.exists)
        XCTAssertEqual(feedback.label, "End")
        XCTAssertEqual(app.staticTexts.matching(identifier: "skipFeedback").count, 1)
        // Hit the overlay's side again: it must not intercept the gesture.
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).doubleTap()
        position(app, near: 20, tolerance: 0)
        XCTAssertEqual(surface.frame, frame)
        expect(feedback, NSPredicate(format: "exists == false"))
        state(app, "Paused")
    }

    @MainActor func testHorizontalSwipeDirectionPriorityAndHoldExclusionInBothOrientations() {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        setSlow(app)
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let surface = app.otherElements["videoSurface"]
            setPosition(app, fraction: 0.5); position(app, near: 15)
            drag(surface, from: 0.4, to: 0.4 + 1.0 / 6.0, endHold: 0.8)
            position(app, near: 25)
            state(app, "Paused")
            XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
            XCTAssertFalse(app.staticTexts["skipFeedback"].exists)
            XCTAssertFalse(app.otherElements["seekPreview"].exists)
            drag(surface, from: 0.6, to: 0.6 - 1.0 / 6.0); position(app, near: 15)
            let before = readPosition(app)
            drag(surface, from: 0.5, to: 0.5, y: 0.4, endY: 0.7)
            position(app, near: before, tolerance: 0)
            drag(surface, from: 0.5, to: 0.5 + 5 / surface.frame.width)
            position(app, near: before, tolerance: 0)
            // Holding first must retain hold ownership even after horizontal movement.
            app.buttons["playPause"].tap(); state(app, "Playing")
            let heldOrigin = readPosition(app)
            drag(surface, from: 0.4, to: 0.4 + 1.0 / 6.0, hold: 0.8, endHold: 0.3)
            let advance = readPosition(app) - heldOrigin
            XCTAssertLessThan(advance, 8, "A held contact must not also commit a 10-second swipe")
            XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
            XCTAssertFalse(app.staticTexts["temporaryRate"].exists)
            state(app, "Playing")
            // A real swipe while playing keeps the selected rate and play intent.
            drag(surface, from: 0.6, to: 0.6 - 1.0 / 6.0)
            state(app, "Playing")
            XCTAssertEqual(app.buttons["rateMenu"].value as? String, "0.25×")
            app.buttons["playPause"].tap(); state(app, "Paused")
            capture("horizontal-seek-\(orientation.rawValue)")
        }
    }

    @MainActor private func assertFrames(_ elements: [XCUIElement], _ frames: [CGRect]) {
        for (element, frame) in zip(elements, frames) {
            let current = element.frame
            XCTAssertEqual(current.minX, frame.minX, accuracy: 0.5)
            XCTAssertEqual(current.minY, frame.minY, accuracy: 0.5)
            XCTAssertEqual(current.width, frame.width, accuracy: 0.5)
            XCTAssertEqual(current.height, frame.height, accuracy: 0.5)
        }
    }
}
