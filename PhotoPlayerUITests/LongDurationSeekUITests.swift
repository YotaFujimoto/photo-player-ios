import XCTest
import UIKit

final class LongDurationSeekUITests: XCTestCase {
    @MainActor func testTwoHourTrackEdgesPortrait() { verify(.portrait) }
    @MainActor func testTwoHourTrackEdgesLandscape() { verify(.landscapeLeft) }
    @MainActor private func verify(_ orientation: UIDeviceOrientation) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.photoPlayerForTesting(); app.launchArguments = ["--playback-diagnostics"]; app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'videoCard.' AND value == '96x64'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let surface = app.otherElements["videoSurface"]
        wait(surface, "value == %@", "Playing")
        app.pauseAfterInitialControlsHide(); wait(surface, "value == %@", "Paused")
        app.playerButton("rateMenu").tap(); app.buttons["0.25×"].tap()
        XCUIDevice.shared.orientation = orientation
        let bar = app.otherElements["seekSlider"]
        let duration = app.staticTexts["playbackDuration"]
        XCTAssertEqual(duration.label, "2:00:00")
        let frame = bar.frame
        // UI automation rounds touch coordinates. Allow one logical point's
        // media span here; native coordinate/AVPlayer tests use exact timestamps.
        let touchTolerance = Int(ceil(7200 / frame.width)) + 1
        XCTAssertGreaterThanOrEqual(frame.height, 44)
        XCTAssertLessThan(app.staticTexts["playbackPosition"].frame.maxX, frame.minX)
        XCTAssertLessThan(frame.maxX, duration.frame.minX)
        for fraction in [0.01, 0.99, 0.19, 0.81] {
            bar.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: fraction < 0.5 ? 0.05 : 0.95)).tap()
            wait(surface, "value == %@", "Paused")
            let expected = Int(7200 * fraction)
            let clock = app.staticTexts["playbackPosition"]
            XCTAssertEqual(XCTWaiter.wait(for: [liveUIExpectation(predicate: NSPredicate { _, _ in
                let measured = clock.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
                return abs(measured - expected) <= touchTolerance
            }, object: nil)], timeout: 15), .completed)
            XCTAssertEqual(bar.frame, frame, "Track frame must not follow the clock's digit count")
        }
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        wait(surface, "value == %@", "Paused")
        let clock = app.staticTexts["playbackPosition"]
        XCTAssertEqual(XCTWaiter.wait(for: [liveUIExpectation(predicate: NSPredicate { _, _ in
            let measured = clock.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
            return abs(measured - 720) <= touchTolerance
        }, object: nil)], timeout: 15), .completed)
        XCTAssertEqual(app.playerButton("rateMenu").value as? String, "0.25×")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "two-hour-track-\(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertFalse(app.descendants(matching: .any)["seekPreview"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["skipFeedback"].exists)
        app.playerButton("closePlayer").tap()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait; app.finishTestApplication()
    }
    @MainActor private func wait(_ item: XCUIElement, _ format: String, _ value: String) {
        XCTAssertEqual(XCTWaiter.wait(for: [liveUIExpectation(predicate: NSPredicate(format: format, value), object: item)], timeout: 15), .completed)
    }
}
