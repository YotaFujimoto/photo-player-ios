import XCTest
import UIKit

final class FullscreenUITests: XCTestCase {
    @MainActor private func openPaused() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--playback-diagnostics"]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'videoCard.' AND value == '320x180'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        state(app, "Playing")
        app.buttons.matching(identifier: "playPause").firstMatch.tap(); state(app, "Paused")
        app.buttons.matching(identifier: "rateMenu").firstMatch.tap()
        app.buttons.matching(identifier: "0.25×").firstMatch.tap()
        return app
    }
    @MainActor private func surface(_ app: XCUIApplication) -> XCUIElement { app.otherElements.matching(identifier: "videoSurface").firstMatch }
    @MainActor private func play(_ app: XCUIApplication) -> XCUIElement { app.buttons.matching(identifier: "playPause").firstMatch }
    @MainActor private func bar(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "seekSlider").firstMatch }
    @MainActor private func expect(_ element: XCUIElement, _ predicate: NSPredicate, timeout: TimeInterval = 10) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout), .completed)
    }
    @MainActor private func state(_ app: XCUIApplication, _ value: String) {
        expect(surface(app), NSPredicate(format: "value == %@", value), timeout: 20)
    }
    @MainActor private func fullCanvas(_ app: XCUIApplication) {
        // XCTest can return from orientation changes during the presentation
        // transform. Wait for the same exact full-screen geometry we assert;
        // do not sample the rotating rectangle or add a fixed sleep.
        let canvas = surface(app)
        expect(canvas, NSPredicate { _, _ in
            let frame = canvas.frame, screen = app.frame
            return screen.width > screen.height && abs(frame.minX - screen.minX) <= 1
                && abs(frame.minY - screen.minY) <= 1 && abs(frame.width - screen.width) <= 1
                && abs(frame.height - screen.height) <= 1
        })
    }
    @MainActor private func observeForFourSeconds() {
        // Deliberately observe longer than the production three-second deadline.
        // This is a timer assertion, not a delay used to make an input succeed.
        let end = ProcessInfo.processInfo.systemUptime + 4
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in ProcessInfo.processInfo.systemUptime >= end }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 6), .completed)
    }
    @MainActor private func seconds(_ app: XCUIApplication) -> Int {
        app.staticTexts.matching(identifier: "playbackPosition").firstMatch.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }
    @MainActor private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor func testLandscapeCanvasSafeControlsAndPortraitPreserved() {
        let app = openPaused()
        defer { XCUIDevice.shared.orientation = .portrait }
        let portrait = surface(app).frame
        XCTAssertLessThan(portrait.height, app.frame.height)
        capture("fullscreen-portrait-feedback-layout")
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            fullCanvas(app)
            let canvas = surface(app).frame, screen = app.frame
            XCTAssertEqual(canvas.minX, screen.minX, accuracy: 1)
            XCTAssertEqual(canvas.minY, screen.minY, accuracy: 1)
            XCTAssertEqual(canvas.width, screen.width, accuracy: 1)
            XCTAssertEqual(canvas.height, screen.height, accuracy: 1)
            let close = app.buttons.matching(identifier: "closePlayer").firstMatch.frame
            let rate = app.buttons.matching(identifier: "rateMenu").firstMatch.frame
            XCTAssertGreaterThanOrEqual(close.minX, 44)
            XCTAssertLessThanOrEqual(rate.maxX, screen.maxX - 44)
            XCTAssertLessThanOrEqual(rate.maxY, screen.maxY - 16)
            XCTAssertGreaterThanOrEqual(bar(app).frame.minX, 44)
            XCTAssertLessThanOrEqual(bar(app).frame.maxX, screen.maxX - 44)
            XCTAssertTrue(play(app).isHittable)
            surface(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            XCTAssertTrue(play(app).exists, "Paused controls remain visible")
            XCTAssertEqual(surface(app).frame, canvas)
            capture("fullscreen-visible-\(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .portrait
        expect(surface(app), NSPredicate { _, _ in self.surface(app).frame == portrait })
        XCTAssertEqual(surface(app).frame, portrait)
        XCTAssertTrue(play(app).isHittable)
    }

    @MainActor func testAutoHideSingleDoubleTapAndSpeedMenuOwnership() {
        let app = openPaused()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        fullCanvas(app)
        let canvas = surface(app).frame
        let origin = seconds(app), began = ProcessInfo.processInfo.systemUptime
        play(app).tap(); state(app, "Playing")
        expect(play(app), NSPredicate(format: "exists == false"), timeout: 7)
        XCTAssertEqual(surface(app).frame, canvas)
        capture("fullscreen-hidden-canvas")
        // The same-size 180-degree rotation must invalidate the old timer too.
        XCUIDevice.shared.orientation = .landscapeRight
        fullCanvas(app)
        XCTAssertTrue(play(app).exists)
        expect(play(app), NSPredicate(format: "exists == false"), timeout: 7)
        surface(app).coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).doubleTap()
        XCTAssertFalse(play(app).exists, "Double tap must not toggle the hidden controls")
        state(app, "Playing")
        surface(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(play(app).waitForExistence(timeout: 3))
        let reached = seconds(app)
        let ordinary = (ProcessInfo.processInfo.systemUptime - began) * 0.25
        XCTAssertEqual(Double(reached - origin) - ordinary, 10, accuracy: 2)
        app.playerButton("rateMenu").press(forDuration: 4)
        let half = app.buttons.matching(identifier: "0.5×").firstMatch
        XCTAssertTrue(half.waitForExistence(timeout: 3))
        observeForFourSeconds()
        XCTAssertTrue(half.isHittable)
        capture("fullscreen-speed-menu")
        half.tap()
        XCTAssertTrue(play(app).exists)
        XCTAssertEqual(app.buttons.matching(identifier: "rateMenu").firstMatch.value as? String, "0.5×")
        expect(play(app), NSPredicate(format: "exists == false"), timeout: 7)
        XCTAssertEqual(surface(app).frame, canvas)
        surface(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(play(app).waitForExistence(timeout: 3))
        play(app).tap(); state(app, "Paused")
        observeForFourSeconds()
        XCTAssertTrue(play(app).exists)
    }

    @MainActor func testHiddenSwipeHeldRateBarAndLifecycleCleanup() {
        let app = openPaused()
        defer { XCUIDevice.shared.orientation = .portrait }
        bar(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        state(app, "Paused")
        XCUIDevice.shared.orientation = .landscapeLeft
        fullCanvas(app)
        play(app).tap(); state(app, "Playing")
        expect(play(app), NSPredicate(format: "exists == false"), timeout: 7)
        let view = surface(app)
        view.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.3)).press(forDuration: 0.05,
            thenDragTo: view.coordinate(withNormalizedOffset: CGVector(dx: 0.6 - 1.0 / 6.0, dy: 0.3)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        state(app, "Playing")
        XCTAssertFalse(play(app).exists)
        XCTAssertFalse(app.otherElements.matching(identifier: "seekPreview").firstMatch.exists)
        view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(play(app).waitForExistence(timeout: 3))
        let start = seconds(app), began = ProcessInfo.processInfo.systemUptime
        view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 4)
        XCTAssertTrue(play(app).exists, "A held gesture must suspend the hide timer")
        let extra = Double(seconds(app) - start) - (ProcessInfo.processInfo.systemUptime - began) * 0.25
        XCTAssertGreaterThan(extra, 4); XCTAssertLessThan(extra, 9)
        XCTAssertFalse(app.staticTexts.matching(identifier: "temporaryRate").firstMatch.exists)
        app.revealPlayerControls()
        let seek = bar(app)
        seek.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 4)
        XCTAssertTrue(play(app).exists, "Bar tracking must suspend the hide timer")
        state(app, "Playing")
        app.playerButton("playPause").tap(); state(app, "Paused")
        XCTAssertEqual(app.buttons.matching(identifier: "rateMenu").firstMatch.value as? String, "0.25×")
        XCTAssertFalse(app.staticTexts.matching(identifier: "skipFeedback").firstMatch.exists)
        capture("fullscreen-after-held-and-bar")
        play(app).tap(); state(app, "Playing")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(play(app).isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(play(app).isHittable)
        XCUIDevice.shared.press(.home); app.activate()
        state(app, "Paused")
        observeForFourSeconds()
        XCTAssertTrue(play(app).exists)
        XCTAssertFalse(app.staticTexts.matching(identifier: "temporaryRate").firstMatch.exists)
        capture("fullscreen-after-background")
        app.buttons.matching(identifier: "closePlayer").firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "videoCard.1").firstMatch.waitForExistence(timeout: 10))
    }
}
