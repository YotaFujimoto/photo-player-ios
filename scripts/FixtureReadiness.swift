// CI-only simulator preparation. Never linked into or packaged with PhotoPlayer.
import UIKit
import Photos
import Darwin

@main
@MainActor final class FixtureReadiness: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var resultURL: URL?
    private var observations: [String] = []

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
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
