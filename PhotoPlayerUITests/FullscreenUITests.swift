import XCTest
import UIKit

final class FullscreenUITests: XCTestCase {
    @MainActor private func openPaused() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.photoPlayerForTesting()
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
    @MainActor private func bar(_ app: XCUIApplication) -> XCUIElement { app.otherElements.matching(identifier: "seekSlider").firstMatch }
    @MainActor private func expect(_ element: XCUIElement, _ predicate: NSPredicate, timeout: TimeInterval = 10) {
        // XCTest's first predicate poll waits about a second even when the
        // state is already true. That consumed the remaining three-second
        // control visibility window after the bar gesture. Observe immediately
        // and wait only if needed, within the SAME total assertion deadline.
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let matches = predicate.evaluate(with: element)
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if matches && remaining >= 0 { return }
        guard remaining > 0 else { XCTFail("State query exceeded its assertion deadline"); return }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: remaining), .completed)
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

    @MainActor private func finish(_ app: XCUIApplication) {
        // All functional assertions run before cleanup. A final unasserted
        // rotation with the player still presented stalled XCTest's animation
        // idle notification after its event loop was already idle. Close using
        // the normal UI before resetting orientation and ending this test host.
        let close = app.buttons.matching(identifier: "closePlayer").firstMatch
        if close.exists { close.tap() }
        XCTAssertTrue(app.buttons.matching(identifier: "videoCard.1").firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        expect(app, NSPredicate { _, _ in app.frame.height > app.frame.width })
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
    }

    @MainActor func testLandscapeCanvasSafeControlsAndPortraitPreserved() {
        let app = openPaused()
        defer { finish(app) }
        let portrait = surface(app).frame
        XCTAssertEqual(portrait.height, app.frame.height, accuracy: 1)
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
            expect(play(app), NSPredicate(format: "exists == false"))
            surface(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            app.waitForRevealedPlayerControls()
            XCTAssertEqual(surface(app).frame, canvas)
            capture("fullscreen-visible-\(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .portrait
        expect(surface(app), NSPredicate { _, _ in self.surface(app).frame == portrait })
        XCTAssertEqual(surface(app).frame, portrait)
        XCTAssertTrue(play(app).isHittable)
    }

    @MainActor func testAutoHideSingleDoubleTapAndPausedControls() {
        let app = openPaused()
        defer { finish(app) }
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
        app.waitForRevealedPlayerControls()
        play(app).tap()
        let stopped = ProcessInfo.processInfo.systemUptime
        state(app, "Paused")
        let reached = seconds(app)
        let ordinary = (stopped - began) * 0.25
        XCTAssertEqual(Double(reached - origin) - ordinary, 10, accuracy: 2)
        observeForFourSeconds()
        XCTAssertTrue(play(app).exists)
    }

    @MainActor func testSpeedMenuPinsControlsThroughPressAndSelection() {
        let app = openPaused()
        defer { finish(app) }
        XCUIDevice.shared.orientation = .landscapeLeft
        fullCanvas(app)
        let canvas = surface(app).frame
        // Target the actual control. An app-root coordinate still lazily
        // snapshots the whole hierarchy at input time and can outlive the
        // three-second deadline, then press the video underneath instead.
        let rateButton = app.buttons.matching(identifier: "rateMenu").firstMatch
        XCTAssertTrue(rateButton.isHittable)
        play(app).tap()
        rateButton.press(forDuration: 4)
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
        app.waitForRevealedPlayerControls()
        play(app).tap(); state(app, "Paused")
        observeForFourSeconds()
        XCTAssertTrue(play(app).exists)
    }

    @MainActor func testHiddenSwipeHeldRateBarAndLifecycleCleanup() {
        let app = openPaused()
        defer { finish(app) }
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
        app.waitForRevealedPlayerControls()
        play(app).tap(); state(app, "Paused")
        // Prepare while paused and anchor to the video, not the app root.
        // This keeps input lookup scoped to the actual interaction surface.
        let holdPoint = view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let start = seconds(app), began = ProcessInfo.processInfo.systemUptime
        play(app).tap()
        holdPoint.press(forDuration: 4)
        XCTAssertTrue(play(app).exists, "A held gesture must suspend the hide timer")
        let extra = Double(seconds(app) - start) - (ProcessInfo.processInfo.systemUptime - began) * 0.25
        XCTAssertGreaterThan(extra, 4); XCTAssertLessThan(extra, 9)
        XCTAssertFalse(app.staticTexts.matching(identifier: "temporaryRate").firstMatch.exists)
        app.playerButton("playPause").tap(); state(app, "Paused")
        let seek = bar(app)
        let barStart = seek.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let barEnd = seek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        play(app).tap()
        barStart.press(forDuration: 0.05, thenDragTo: barEnd,
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
