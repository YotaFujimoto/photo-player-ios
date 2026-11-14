import XCTest
import Photos
import AVFoundation
import UIKit
@testable import PhotoPlayer

/// Real 7200-second media with continuous timestamps, not a substituted UI duration.
final class LongDurationPlaybackTests: XCTestCase {
    @MainActor func testTwoHourPhotoKitVideoEdgeSeeksMeasuredCompletionAndPlaybackIntent() async throws {
        let options = PHFetchOptions(); options.predicate = NSPredicate(format: "duration > 7100")
        let asset = try XCTUnwrap(PHAsset.fetchAssets(with: .video, options: options).firstObject)
        XCTAssertEqual(asset.duration, 7200, accuracy: 0.2)
        let model = PlaybackModel(asset: asset)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController(); window.rootViewController = controller; window.makeKeyAndVisible()
        let surface = VideoGestureView(frame: window.bounds); controller.view.addSubview(surface)
        model.connectVideoOutput(surface.playerLayer)
        defer { model.close(); window.isHidden = true; previous?.makeKey() }
        model.load(); try await ready { model.player.timeControlStatus == .playing }
        model.pause(); model.setRate(0.25)
        for target in [0.0, 1, 72, 1368, 3599, 3600, 3601, 5832, 7128, 7199.9, 72] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target)
            XCTAssertEqual(model.displayedPosition, target, accuracy: 0.001)
            model.endScrubbing()
            try await ready { !model.isSeeking }
            try await ready { surface.playerLayer.isReadyForDisplay }
            XCTAssertTrue(surface.playerLayer.player === model.player)
            XCTAssertEqual(model.player.currentTime().seconds, target, accuracy: 0.001)
            XCTAssertEqual(model.position, target, accuracy: 0.001)
            XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
            XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
            print("TwoHour seek requested=\(target) measured=\(model.player.currentTime().seconds) loaded=\(model.player.currentItem!.loadedTimeRanges) seekable=\(model.player.currentItem!.seekableTimeRanges)")
        }
        model.togglePlayback(); try await ready { model.player.timeControlStatus == .playing }
        XCTAssertTrue(model.beginScrubbing()); model.scrub(to: 7128); model.endScrubbing()
        try await ready { !model.isSeeking && model.player.timeControlStatus == .playing }
        XCTAssertTrue(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0.25)
        XCTAssertEqual(model.player.currentTime().seconds, 7128, accuracy: 0.5)
    }
    @MainActor private func ready(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() {
            guard ContinuousClock.now < deadline else { XCTFail("Two-hour media operation exceeded 15 seconds"); throw NSError(domain: "LongDuration", code: 1) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
