import XCTest
import Photos
import AVFoundation
import UIKit
import SwiftUI
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
        try await ready(seeking: true) { !model.isSeeking }
        XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.001)
        // Verify AVPlayer's measured destination after its completion too,
        // not only optimistic UI labels.
        for target in [7.5, 22.5, 15.0] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target); model.endScrubbing()
            try await ready(seeking: true) { !model.isSeeking }
            XCTAssertEqual(model.player.currentTime().seconds, target, accuracy: 0.001)
            XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
            XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
        }
    }

    @MainActor private func ready(seeking: Bool = false, _ predicate: () -> Bool) async throws {
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(15))
        var captured = false
        while !predicate() {
            // Trigger read-only capture only for an unusually long native seek,
            // not for the intentional playback-to-4.25s precondition below.
            if seeking && !captured && ContinuousClock.now >= started.advanced(by: .seconds(2)) {
                FileHandle.standardOutput.write(Data("CI_CAPTURE_SEEK_WAIT pid=\(ProcessInfo.processInfo.processIdentifier)\n".utf8))
                captured = true
            }
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
        // The plain UIKit layer test above remains as a comparison. This
        // second case includes the production SwiftUI bridge, glass overlays,
        // and seek control, which were absent from the prior native test.
        let controller = UIHostingController(rootView: LongGOPPlayerHarness(model: model))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { model.close(); window.isHidden = true; previous?.makeKey() }
        model.load()
        // Reproduce the observed UI condition: actual playback has advanced
        // beyond four seconds before pausing. This is a media-state condition,
        // not a delay added to seeking or a replacement for the early-pause test.
        try await ready { model.player.timeControlStatus == .playing && model.player.currentTime().seconds >= 4.25 }
        model.pause(); model.setRate(0.25)
        // The UI failure paused for about six seconds while selecting speed
        // and locating the bar. Exercise that idle-player condition here too.
        // This is a test input, never a delay in the application's seek path.
        let pausedPosition = model.player.currentTime().seconds
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(model.player.currentTime().seconds, pausedPosition, accuracy: 0.001)
        XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
        let bar = try XCTUnwrap(findBar(in: controller.view))
        XCTAssertGreaterThan(bar.bounds.width, 0)
        print("LongGOP production view pause at \(model.player.currentTime().seconds)")
        // Also cover overlapping committed requests after actual playback,
        // rather than testing overlap only at the very beginning of the clip.
        for target in [7.5, 22.5, 15.0] {
            let x = bar.bounds.width * CGFloat(target / model.duration)
            XCTAssertTrue(bar.start(at: x)); bar.finish(at: x)
        }
        try await ready(seeking: true) { !model.isSeeking }
        XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.001)
        XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
        XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
        for target in [7.5, 22.5, 15.0] {
            XCTAssertTrue(model.beginScrubbing()); model.scrub(to: target); model.endScrubbing()
            try await ready(seeking: true) { !model.isSeeking }
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

    @MainActor private func findBar(in view: UIView) -> SeekBarControl? {
        if let bar = view as? SeekBarControl { return bar }
        return view.subviews.lazy.compactMap { self.findBar(in: $0) }.first
    }
}

@MainActor private struct LongGOPPlayerHarness: View {
    @ObservedObject var model: PlaybackModel
    var body: some View {
        ZStack {
            PlayerSurface(model: model, fullscreen: true).ignoresSafeArea()
            Image(systemName: "play.fill").font(.system(size: 34)).frame(width: 80, height: 80).mediaGlass()
            VStack {
                Spacer()
                SeekBar(position: model.displayedPosition, duration: model.duration, enabled: model.isReady,
                        cancellationID: model.gestureCancellationID, onBegin: model.beginScrubbing,
                        onChange: model.scrub, onCommit: model.endScrubbing, onCancel: model.cancelScrubbing)
                    .frame(height: 44).padding(12).mediaGlass()
            }.padding(12)
        }.foregroundStyle(.white).tint(.white).background(.black)
    }
}
