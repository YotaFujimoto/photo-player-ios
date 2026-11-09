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
        if !held { state(app, "Playing"); app.buttons.matching(identifier: "playPause").firstMatch.tap(); state(app, "Paused") }
        return app
    }
    @MainActor private func bar(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "seekSlider").firstMatch }
    @MainActor private func setPosition(_ app: XCUIApplication, fraction: CGFloat, y: CGFloat = 0.5) {
        bar(app).coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: y)).tap()
    }
    @MainActor private func state(_ app: XCUIApplication, _ value: String) {
        expect(app.buttons.matching(identifier: "playPause").firstMatch, NSPredicate(format: "value == %@", value))
    }
    @MainActor private func expect(_ element: XCUIElement, _ predicate: NSPredicate) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
    }
    @MainActor private func position(_ app: XCUIApplication, near seconds: Int, tolerance: Int = 1) {
        expect(app.staticTexts.matching(identifier: "playbackPosition").firstMatch, NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement else { return false }
            let value = element.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
            return abs(value - seconds) <= tolerance
        })
    }
    @MainActor private func readPosition(_ app: XCUIApplication) -> Int {
        app.staticTexts.matching(identifier: "playbackPosition").firstMatch.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
    @MainActor private func setSlow(_ app: XCUIApplication) {
        app.buttons.matching(identifier: "rateMenu").firstMatch.tap(); app.buttons.matching(identifier: "0.25×").firstMatch.tap()
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

    @MainActor func testBarTapDragAndPlaybackIntentPortrait() { verifyBar(in: .portrait) }
    @MainActor func testBarTapDragAndPlaybackIntentLandscape() { verifyBar(in: .landscapeLeft) }

    @MainActor private func verifyBar(in orientation: UIDeviceOrientation) {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        setSlow(app)
        XCUIDevice.shared.orientation = orientation
        // These identifiers each belong to one production control. Check
        // uniqueness once, then stop AX traversal at the known first match.
        XCTAssertEqual(app.buttons.matching(identifier: "playPause").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "seekSlider").count, 1)
        XCTAssertGreaterThanOrEqual(bar(app).frame.height, 44)
        setPosition(app, fraction: 0.25, y: 0.05); position(app, near: 7)
        setPosition(app, fraction: 0.75, y: 0.95); position(app, near: 22)
        drag(bar(app), from: 0.2, to: 0.5); position(app, near: 15)
        state(app, "Paused")
        XCTAssertFalse(app.staticTexts.matching(identifier: "skipFeedback").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(identifier: "temporaryRate").firstMatch.exists)
        XCTAssertFalse(app.otherElements.matching(identifier: "seekPreview").firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "rateMenu").firstMatch.value as? String, "0.25×")
        let pauseFrame = app.buttons.matching(identifier: "playPause").firstMatch.frame
        let pausePoint = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: pauseFrame.midX, dy: pauseFrame.midY))
        pausePoint.tap(); state(app, "Playing")
        setPosition(app, fraction: 0.25)
        let seekReturned = ProcessInfo.processInfo.systemUptime
        state(app, "Playing")
        pausePoint.tap()
        let pauseReturned = ProcessInfo.processInfo.systemUptime
        state(app, "Paused")
        // AX queries may take seconds while playback correctly advances.
        // Keep the original ±2s tolerance around the elapsed 0.25× target.
        let expected = min(30, Int(7.5 + (pauseReturned - seekReturned) * 0.25))
        position(app, near: expected, tolerance: 2)
        XCTAssertEqual(app.buttons.matching(identifier: "rateMenu").firstMatch.value as? String, "0.25×")
        // Continuous tracking beyond the edge reaches the exact endpoints.
        drag(bar(app), from: 0.5, to: 1.02); position(app, near: 30, tolerance: 0)
        drag(bar(app), from: 0.5, to: -0.02); position(app, near: 0, tolerance: 0)
        capture("bar-tap-drag-\(orientation.rawValue)")
    }

    @MainActor func testLoadingErrorAndSeekOverlaysNeverMoveNormalControls() {
        let app = open(held: true)
        let release = app.buttons.matching(identifier: "releasePlayerResult").firstMatch
        XCTAssertTrue(release.waitForExistence(timeout: 20))
        let elements = [app.otherElements.matching(identifier: "videoSurface").firstMatch, bar(app), app.buttons.matching(identifier: "playPause").firstMatch, app.buttons.matching(identifier: "rateMenu").firstMatch]
        let frames = elements.map(\.frame)
        app.buttons.matching(identifier: "cancelDownload").firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "retryVideo").firstMatch.waitForExistence(timeout: 10))
        assertFrames(elements, frames)
        app.buttons.matching(identifier: "retryVideo").firstMatch.tap()
        expect(release, NSPredicate(format: "enabled == true"))
        assertFrames(elements, frames)
        capture("loading-overlay-fixed-layout")
        release.tap(); state(app, "Playing")
        assertFrames(elements, frames)
        app.buttons.matching(identifier: "playPause").firstMatch.tap(); state(app, "Paused")
        setPosition(app, fraction: 0.5); position(app, near: 15)
        assertFrames(elements, frames)
        XCTAssertFalse(app.staticTexts.matching(identifier: "Buffering…").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(identifier: "Buffering...").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(identifier: "playerState").firstMatch.exists)
        capture("normal-seek-fixed-layout")
    }

    @MainActor func testSkipFeedbackIsBoundedReplacedAndDoesNotBlockInput() {
        let app = open()
        let surface = app.otherElements.matching(identifier: "videoSurface").firstMatch
        setPosition(app, fraction: 0.5); position(app, near: 15)
        let frame = surface.frame
        let right = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        right.doubleTap()
        let feedback = app.staticTexts.matching(identifier: "skipFeedback").firstMatch
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

    @MainActor func testHorizontalSwipePriorityAndHoldExclusionPortrait() { verifyHorizontal(in: .portrait) }
    @MainActor func testHorizontalSwipePriorityAndHoldExclusionLandscape() { verifyHorizontal(in: .landscapeLeft) }

    @MainActor private func verifyHorizontal(in orientation: UIDeviceOrientation) {
        let app = open()
        defer { XCUIDevice.shared.orientation = .portrait }
        setSlow(app)
        XCUIDevice.shared.orientation = orientation
        let surface = app.otherElements.matching(identifier: "videoSurface").firstMatch
        setPosition(app, fraction: 0.5); position(app, near: 15)
        drag(surface, from: 0.4, to: 0.4 + 1.0 / 6.0, endHold: 0.8)
        position(app, near: 25)
        state(app, "Paused")
        XCTAssertFalse(app.staticTexts.matching(identifier: "temporaryRate").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(identifier: "skipFeedback").firstMatch.exists)
        XCTAssertFalse(app.otherElements.matching(identifier: "seekPreview").firstMatch.exists)
        drag(surface, from: 0.6, to: 0.6 - 1.0 / 6.0); position(app, near: 15)
        let before = readPosition(app)
        drag(surface, from: 0.5, to: 0.5, y: 0.4, endY: 0.7)
        position(app, near: before, tolerance: 0)
        drag(surface, from: 0.5, to: 0.5 + 5 / surface.frame.width)
        position(app, near: before, tolerance: 0)
        // Holding first must retain hold ownership even after horizontal movement.
        app.buttons.matching(identifier: "playPause").firstMatch.tap(); state(app, "Playing")
        let heldOrigin = readPosition(app)
        let heldStarted = ProcessInfo.processInfo.systemUptime
        drag(surface, from: 0.4, to: 0.4 + 1.0 / 6.0, hold: 0.8, endHold: 0.3)
        let advance = readPosition(app) - heldOrigin
        let ordinaryAdvance = (ProcessInfo.processInfo.systemUptime - heldStarted) * 0.25
        XCTAssertLessThan(Double(advance) - ordinaryAdvance, 6.5,
                          "A held contact must not also commit a 10-second swipe")
        XCTAssertEqual(app.buttons.matching(identifier: "rateMenu").firstMatch.value as? String, "0.25×")
        XCTAssertFalse(app.staticTexts.matching(identifier: "temporaryRate").firstMatch.exists)
        state(app, "Playing")
        // A real swipe while playing keeps the selected rate and play intent.
        drag(surface, from: 0.6, to: 0.6 - 1.0 / 6.0)
        state(app, "Playing")
        XCTAssertEqual(app.buttons.matching(identifier: "rateMenu").firstMatch.value as? String, "0.25×")
        app.buttons.matching(identifier: "playPause").firstMatch.tap(); state(app, "Paused")
        capture("horizontal-seek-\(orientation.rawValue)")
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
