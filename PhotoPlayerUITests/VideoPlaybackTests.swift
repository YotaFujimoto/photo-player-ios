import XCTest
import UIKit

final class VideoPlaybackTests: XCTestCase {
    @MainActor
    func testPhotoKitVideoPlaybackRateAndSeek() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--playback-diagnostics"]
        app.launch()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'videoCard.'"))
        let card = cards.matching(NSPredicate(format: "value == '320x180'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertEqual(cards.count, 12, "Only the twelve synthetic videos, not still images, should be listed")
        XCTAssertTrue(card.images["videoThumbnail"].waitForExistence(timeout: 15))
        screenshot("video-library")
        card.tap()

        app.buttons["playerDiagnostics"].tap()
        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        waitForLabel(state, "Playing", timeout: 30)
        app.buttons["playPause"].tap()
        waitForLabel(state, "Paused")

        app.buttons["rateMenu"].tap()
        app.buttons["0.25×"].tap()
        XCTAssertTrue((app.buttons["rateMenu"].value as? String ?? "").contains("0.25"))
        app.buttons["playPause"].tap()
        waitForLabel(state, "Playing")
        let initialPosition = app.staticTexts["playbackPosition"].label
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", initialPosition), object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 12), .completed)
        app.buttons["Playback details"].tap()
        let actualRate = app.staticTexts["actualRate"]
        XCTAssertTrue(actualRate.waitForExistence(timeout: 5))
        let slowRate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '0.25'"), object: actualRate)
        XCTAssertEqual(XCTWaiter.wait(for: [slowRate], timeout: 10), .completed)
        screenshot("video-slow-playback")
        app.buttons["playPause"].tap()
        waitForLabel(state, "Paused")

        dragSlider(app, to: 0.5)
        let middle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label IN %@", ["0:14", "0:15", "0:16"]), object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [middle], timeout: 15), .completed)
        waitForLabel(state, "Paused")
        app.buttons["playPause"].tap()
        waitForLabel(state, "Playing")
        let seekStarted = ProcessInfo.processInfo.systemUptime
        // While playing the thumb keeps moving; let XCTest resolve its current
        // value instead of estimating a grab point from a rounded clock label.
        app.sliders["seekSlider"].adjust(toNormalizedSliderPosition: 0.75)
        waitForLabel(state, "Playing")
        let resumedSlow = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '0.25'"), object: actualRate)
        XCTAssertEqual(XCTWaiter.wait(for: [resumedSlow], timeout: 10), .completed)
        // XCTest's slider gesture is approximate, and playback keeps advancing while
        // the state/rate assertions query the UI. Advance the same 22...24-second
        // acceptance window at the verified 0.25 rate instead of waiting for the past.
        let movingPosition = NSPredicate { candidate, _ in
            let elapsed = ProcessInfo.processInfo.systemUptime - seekStarted
            let expectedLabels = (22...24).map {
                String(format: "0:%02d", min(30, Int(Double($0) + elapsed * 0.25)))
            }
            return NSPredicate(format: "label IN %@", expectedLabels).evaluate(with: candidate)
        }
        let later = XCTNSPredicateExpectation(predicate: movingPosition, object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [later], timeout: 15), .completed)
        app.buttons["playPause"].tap()
        waitForLabel(state, "Paused")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["playPause"].isHittable)
        screenshot("video-landscape-seek")
        app.buttons["closePlayer"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["playPause"].exists)
    }

    @MainActor
    private func dragSlider(_ app: XCUIApplication, to fraction: CGFloat) {
        let slider = app.sliders["seekSlider"]
        @MainActor func seconds(_ identifier: String) -> Double {
            app.staticTexts[identifier].label.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
        }
        let duration = seconds("playbackDuration")
        XCTAssertGreaterThan(duration, 0)
        // Grab within the thumb using the displayed second's midpoint, then
        // drag to a fixed track coordinate. XCTest's approximate adjustment
        // previously ended at 17.24s despite requesting 50% of a 30s video.
        let current = CGFloat(min(1, max(0, (seconds("playbackPosition") + 0.5) / duration)))
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: current, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
    }

    @MainActor
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
