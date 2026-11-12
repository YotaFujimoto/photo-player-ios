import XCTest

extension XCUIApplication {
    /// Begin test setup from an observed visibility cycle, rather than racing
    /// a partially spent initial timer after slow accessibility startup.
    /// Call only after asserting Playing in a non-diagnostic player.
    @MainActor func pauseAfterInitialControlsHide(file: StaticString = #filePath, line: UInt = #line) {
        let play = buttons.matching(identifier: "playPause").firstMatch
        let hidden = liveUIExpectation(predicate: NSPredicate(format: "exists == false"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 15), .completed, file: file, line: line)
        revealPlayerControls()
        play.tap()
    }

    /// Poll from now, within the original three-second assertion deadline.
    /// A tap can return before UIKit's double-tap failure dependency resolves;
    /// XCTest's waitForExistence first polls about a second later. Neither an
    /// immediate one-shot query nor that initial polling gap fits this UI.
    @MainActor func waitForRevealedPlayerControls(file: StaticString = #filePath, line: UInt = #line) {
        let play = buttons.matching(identifier: "playPause").firstMatch
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        repeat {
            let visible = play.exists
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            if visible { return }
            // Yield the test runner between observations, never delay an input
            // once the expected state is visible or retry the user's tap.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        } while ProcessInfo.processInfo.systemUptime < deadline
        XCTFail("Player controls did not appear within 3 seconds", file: file, line: line)
    }

    /// Explicitly use the new single-tap UI when a test needs a hidden control.
    /// Never retries an input or changes application auto-hide timing.
    @MainActor func revealPlayerControls() {
        let play = buttons.matching(identifier: "playPause").firstMatch
        if !play.exists {
            otherElements.matching(identifier: "videoSurface").firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            waitForRevealedPlayerControls()
        }
    }
    @MainActor func playerButton(_ identifier: String) -> XCUIElement {
        revealPlayerControls()
        return buttons.matching(identifier: identifier).firstMatch
    }
}
