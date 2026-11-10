import XCTest

extension XCUIApplication {
    /// Explicitly use the new single-tap UI when a test needs a hidden control.
    /// Never retries an input or changes application auto-hide timing.
    @MainActor func revealPlayerControls() {
        let play = buttons.matching(identifier: "playPause").firstMatch
        if !play.exists {
            otherElements.matching(identifier: "videoSurface").firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            // The tap synchronizes the UI; avoid the one-second first polling
            // interval spending a third of the real auto-hide window.
            XCTAssertTrue(play.exists)
        }
    }
    @MainActor func playerButton(_ identifier: String) -> XCUIElement {
        revealPlayerControls()
        return buttons.matching(identifier: identifier).firstMatch
    }
}
