// CI-only simulator preparation. Never linked into or packaged with PhotoPlayer.
import UIKit
import Photos
import Darwin

@main
@MainActor final class FixtureReadiness: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        guard let argument = CommandLine.arguments.last, let expected = Int(argument), expected >= 12 else {
            finish("FIXTURE_ARGUMENT_ERROR", code: 64)
        }
        Task { await inspect(expected: expected) }
        return true
    }

    private func inspect(expected: Int) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var lastCount = -1
        repeat {
            let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard access == .authorized else { finish("FIXTURE_ACCESS_ERROR status=\(access.rawValue)", code: 1) }
            let videos = PHAsset.fetchAssets(with: .video, options: nil)
            if videos.count != lastCount {
                print("FIXTURE_AVAILABLE videos=\(videos.count) expected=\(expected)")
                fflush(nil)
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
        print(message)
        fflush(nil)
        exit(code)
    }
}
