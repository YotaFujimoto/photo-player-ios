// CI-only simulator preparation. Never linked into or packaged with PhotoPlayer.
import UIKit
import Photos
import Darwin

@main
@MainActor final class FixtureReadiness: UIResponder, UIApplicationDelegate {
    private var resultURL: URL?
    private var observations: [String] = []
    private var expectedVideos = 0

    static func main() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--result-token"), index + 1 < arguments.count,
              let token = UUID(uuidString: arguments[index + 1]) else { exit(64) }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            try "FIXTURE_PROCESS_STARTED\n".write(
                to: documents.appendingPathComponent("readiness-\(token.uuidString.lowercased()).txt"),
                atomically: true, encoding: .utf8)
        } catch { print("FIXTURE_PROCESS_REPORT_ERROR"); fflush(nil); exit(74) }
        exit(UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(FixtureReadiness.self)))
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let arguments = CommandLine.arguments
        guard let countIndex = arguments.firstIndex(of: "--expected-videos"), countIndex + 1 < arguments.count,
              let expected = Int(arguments[countIndex + 1]), expected >= 12,
              let tokenIndex = arguments.firstIndex(of: "--result-token"), tokenIndex + 1 < arguments.count,
              let token = UUID(uuidString: arguments[tokenIndex + 1]) else {
            finish("FIXTURE_ARGUMENT_ERROR", code: 64)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        resultURL = documents.appendingPathComponent("readiness-\(token.uuidString.lowercased()).txt")
        record("FIXTURE_STARTED")
        expectedVideos = expected
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Fixture readiness", sessionRole: session.role)
        configuration.delegateClass = FixtureScene.self
        return configuration
    }

    func inspectFromActiveScene() {
        record("FIXTURE_SCENE_ACTIVE")
        Task { await inspect(expected: expectedVideos) }
    }

    private func inspect(expected: Int) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var lastCount = -1
        repeat {
            let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard access == .authorized else { finish("FIXTURE_ACCESS_ERROR status=\(access.rawValue)", code: 1) }
            let videos = PHAsset.fetchAssets(with: .video, options: nil)
            if videos.count != lastCount {
                record("FIXTURE_AVAILABLE videos=\(videos.count) expected=\(expected)")
                lastCount = videos.count
            }
            let hasPlaybackFixture = (0..<videos.count).contains {
                let video = videos.object(at: $0)
                return video.pixelWidth == 320 && video.pixelHeight == 180 && abs(video.duration - 30) < 0.1
            }
            if videos.count == expected && hasPlaybackFixture {
                finish("FIXTURE_READY videos=\(expected)", code: 0)
            }
            if videos.count > expected { finish("FIXTURE_UNEXPECTED_EXTRA_VIDEOS", code: 1) }
            // Observe the condition, without touching the library or exercising
            // playback/decoding. UI test deadlines begin after setup, unchanged.
            try? await Task.sleep(nanoseconds: 100_000_000)
        } while ContinuousClock.now < deadline
        finish("FIXTURE_NOT_READY videos=\(lastCount) expected=\(expected)", code: 1)
    }

    private func finish(_ message: String, code: Int32) -> Never {
        record(message)
        exit(code)
    }

    private func record(_ message: String) {
        print(message)
        fflush(nil)
        observations.append(message)
        if let resultURL {
            do { try (observations.joined(separator: "\n") + "\n").write(to: resultURL, atomically: true, encoding: .utf8) }
            catch { print("FIXTURE_REPORT_WRITE_FAILED"); fflush(nil); exit(74) }
        }
    }
}

@MainActor final class FixtureScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var started = false
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !started, let app = UIApplication.shared.delegate as? FixtureReadiness else { return }
        started = true
        app.inspectFromActiveScene()
    }
}
