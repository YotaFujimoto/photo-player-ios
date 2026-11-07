import XCTest

final class VideoPlaybackTests: XCTestCase {
    @MainActor
    func testPhotoKitVideoPlaybackRateAndSeek() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let card = app.buttons.matching(identifier: "videoCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(identifier: "videoCard").count, 1, "Only the synthetic video, not still images, should be listed")
        XCTAssertTrue(app.images["videoThumbnail"].waitForExistence(timeout: 15))
        screenshot("video-library")
        card.tap()

        let state = app.staticTexts["playerState"]
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        waitForLabel(state, "再生中", timeout: 30)
        app.buttons["playPause"].tap()
        waitForLabel(state, "一時停止")

        app.buttons["rateMenu"].tap()
        app.buttons["0.25×"].tap()
        XCTAssertTrue(app.buttons["rateMenu"].label.contains("0.25"))
        app.buttons["playPause"].tap()
        waitForLabel(state, "再生中")
        let initialPosition = app.staticTexts["playbackPosition"].label
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", initialPosition), object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 12), .completed)
        app.buttons["playbackDetails"].tap()
        let actualRate = app.staticTexts["actualRate"]
        XCTAssertTrue(actualRate.waitForExistence(timeout: 5))
        let slowRate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '0.25'"), object: actualRate)
        XCTAssertEqual(XCTWaiter.wait(for: [slowRate], timeout: 10), .completed)
        screenshot("video-slow-playback")
        app.buttons["playPause"].tap()
        waitForLabel(state, "一時停止")

        let slider = app.sliders["seekSlider"]
        slider.adjust(toNormalizedSliderPosition: 0.5)
        let middle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label IN %@", ["0:14", "0:15", "0:16"]), object: app.staticTexts["playbackPosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [middle], timeout: 15), .completed)
        waitForLabel(state, "一時停止")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["playPause"].isHittable)
        screenshot("video-landscape-seek")
        app.buttons["closePlayer"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["playPause"].exists)
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
