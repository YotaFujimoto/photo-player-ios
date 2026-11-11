import XCTest

extension XCUIApplication {
    @MainActor static func photoPlayerForTesting() -> XCUIApplication {
        let app = XCUIApplication()
        // Retain media-service errors from the app while investigating absent
        // AVPlayer completions. The runner's scheme still suppresses activity.
        // This launch environment is not part of the archived application.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "default"
        return app
    }
}
