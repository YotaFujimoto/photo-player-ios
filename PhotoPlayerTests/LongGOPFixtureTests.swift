import XCTest
import Photos
import AVFoundation
import UIKit
@testable import PhotoPlayer

/// Run only after CI imports the original encoding, following the 12-video suite.
final class LongGOPFixtureTests: XCTestCase {
    @MainActor
    func testOriginalEarlyPauseAndQueuedExactSeeksWithPlayerLayer() async throws {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let asset = try XCTUnwrap(PHAsset.fetchAssets(with: .video, options: options).firstObject)
        let model = PlaybackModel(asset: asset)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let layer = AVPlayerLayer(player: model.player)
        layer.frame = controller.view.bounds
        XCTAssertGreaterThan(layer.bounds.width, 0)
        XCTAssertGreaterThan(layer.bounds.height, 0)
        controller.view.layer.addSublayer(layer)
        defer { model.close(); layer.player = nil; window.isHidden = true; previous?.makeKey() }
        model.load()
        try await ready { model.player.timeControlStatus == .playing }
        // Pause at the first Playing observation, without waiting for the
        // control timer or a minimum playback time. Preserve that regression
        // condition independently of XCTest's accessibility startup latency.
        model.pause(); model.setRate(0.25)
        let earlyPosition = model.player.currentTime().seconds
        print("LongGOP early pause at \(earlyPosition)")
        for target in [7.5, 22.5, 15.0] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target); model.endScrubbing()
        }
        try await ready { !model.isSeeking }
        XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.001)
        // Verify AVPlayer's measured destination after its completion too,
        // not only optimistic UI labels.
        for target in [7.5, 22.5, 15.0] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target); model.endScrubbing()
            try await ready { !model.isSeeking }
            XCTAssertEqual(model.player.currentTime().seconds, target, accuracy: 0.001)
            XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
            XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
        }
    }

    @MainActor private func ready(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Native long-GOP player did not complete within 15 seconds")
                throw NSError(domain: "LongGOPFixtureTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    func testOriginalSeekAfterPlaybackWithProductionVideoView() async throws {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let asset = try XCTUnwrap(PHAsset.fetchAssets(with: .video, options: options).firstObject)
        let model = PlaybackModel(asset: asset)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController()
        let view = VideoGestureView()
        view.playerLayer.player = model.player
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { model.close(); view.playerLayer.player = nil; window.isHidden = true; previous?.makeKey() }
        model.load()
        // Reproduce the observed UI condition: actual playback has advanced
        // beyond four seconds before pausing. This is a media-state condition,
        // not a delay added to seeking or a replacement for the early-pause test.
        try await ready { model.player.timeControlStatus == .playing && model.player.currentTime().seconds >= 4.25 }
        model.pause(); model.setRate(0.25)
        print("LongGOP production view pause at \(model.player.currentTime().seconds)")
        // Also cover overlapping committed requests after actual playback,
        // rather than testing overlap only at the very beginning of the clip.
        for target in [7.5, 22.5, 15.0] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target); model.endScrubbing()
        }
        try await ready { !model.isSeeking }
        XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.001)
        XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
        XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
        for target in [7.5, 22.5, 15.0] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target); model.endScrubbing()
            try await ready { !model.isSeeking }
            print("LongGOP production view completed \(target) measured=\(model.player.currentTime().seconds)")
            XCTAssertEqual(model.player.currentTime().seconds, target, accuracy: 0.001)
            XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
            XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
        }
    }

    func testOriginalFixtureIsNewestPhotoKitVideo() throws {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let videos = PHAsset.fetchAssets(with: .video, options: options)
        XCTAssertEqual(videos.count, 13)
        let first = try XCTUnwrap(videos.firstObject)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-02-01T00:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(first.creationDate).timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(first.pixelWidth, 320)
        XCTAssertEqual(first.pixelHeight, 180)
        XCTAssertEqual(first.duration, 30, accuracy: 0.1)
    }
}
