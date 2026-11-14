import XCTest

/// Keep each original predicate and timeout, but do not ask XCTest to describe
/// an XCUIElement's entire hierarchy when the predicate is temporarily false.
/// The live element is still queried on every evaluation. In CI a transient
/// Loading state triggered 21.95s of debug-description collection even though
/// the app entered Playing; that traversal consumed the 15s assertion deadline.
/// Normal failure records, screenshots and xcresult evidence remain enabled.
func liveUIExpectation(predicate: NSPredicate, object: Any?) -> XCTNSPredicateExpectation {
    let condition = NSPredicate { _, _ in predicate.evaluate(with: object) }
    return XCTNSPredicateExpectation(predicate: condition, object: nil)
}

extension XCUIApplication {
    @MainActor func finishTestApplication(file: StaticString = #filePath, line: UInt = #line) {
        // End this test's process directly. An extra Home transition here left
        // XCTest reporting foreground while the captured screen was already
        // SpringBoard, after all selection/return assertions had passed.
        // Actual background/restore behavior remains asserted separately in
        // InputLifecycle, Fullscreen and PlaybackGesture tests.
        print("CI_APP_CLEANUP terminate initial=\(state.rawValue)")
        terminate()
        print("CI_APP_CLEANUP terminated=\(state.rawValue)")
        XCTAssertEqual(state, .notRunning, file: file, line: line)
    }

    @MainActor static func photoPlayerForTesting() -> XCUIApplication {
        let app = XCUIApplication()
        // Restoring the full activity stream reproduced megabytes of injected
        // AX hierarchy logs and slow control lookup. Preserve print-based
        // state traces and the separate read-only media-service failure log.
        // This launch environment is not part of the archived application.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        return app
    }
}
