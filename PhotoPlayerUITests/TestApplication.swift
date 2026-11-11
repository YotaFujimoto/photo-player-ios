import XCTest

extension XCUIApplication {
    @MainActor func finishTestApplication(file: StaticString = #filePath, line: UInt = #line) {
        if state == .runningForeground {
            XCUIDevice.shared.press(.home)
            let background = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d OR state == %d",
                Int(State.runningBackground.rawValue), Int(State.runningBackgroundSuspended.rawValue)), object: self)
            XCTAssertEqual(XCTWaiter.wait(for: [background], timeout: 10), .completed, file: file, line: line)
        }
        terminate()
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
