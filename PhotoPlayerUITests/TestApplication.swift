import XCTest

extension XCUIApplication {
    @MainActor static func photoPlayerForTesting() -> XCUIApplication {
        let app = XCUIApplication()
        // Xcode's injected accessibility logging generated megabytes of
        // hierarchy dumps while timing a three-second UI. Suppress only OS
        // activity output in test processes; print-based playback traces,
        // XCTest assertions/actions, screenshots and in-app copy stay intact.
        // This environment is not part of the archived application.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        return app
    }
}
