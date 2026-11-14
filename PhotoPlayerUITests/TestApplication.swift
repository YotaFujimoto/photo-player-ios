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
        var backgroundResult = XCTWaiter.Result.completed
        var observed = state
        print("CI_APP_CLEANUP initial=\(observed.rawValue)")
        if state == .runningForeground {
            XCUIDevice.shared.press(.home)
            let started = ProcessInfo.processInfo.systemUptime
            // Read the public enum directly, including an immediate observation;
            // do not depend on KVC conversion of application.state. Keep the
            // same background/suspended condition and total ten-second budget.
            let condition = NSPredicate { _, _ in
                let current = self.state
                if current != observed { print("CI_APP_CLEANUP observed=\(current.rawValue)"); observed = current }
                return current == .runningBackground || current == .runningBackgroundSuspended
            }
            if !condition.evaluate(with: nil) {
                backgroundResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: nil)],
                    timeout: max(0, 10 - (ProcessInfo.processInfo.systemUptime - started)))
            }
        }
        // Always request termination before an assertion can abort cleanup.
        // A failed background wait remains a failure, never a silent retry.
        terminate()
        print("CI_APP_CLEANUP terminated=\(state.rawValue) backgroundResult=\(backgroundResult.rawValue)")
        XCTAssertEqual(backgroundResult, .completed, "Last pre-termination state: \(observed.rawValue)", file: file, line: line)
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
