import XCTest
import Photos
import AVFoundation
import UIKit
import SwiftUI
import MachO
@testable import PhotoPlayer

/// Run only after CI imports the original encoding, following the 12-video suite.
final class LongGOPFixtureTests: XCTestCase {
    @MainActor
    func testOriginalEarlyPauseAndQueuedExactSeeksWithPlayerLayer() async throws {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let asset = try XCTUnwrap(PHAsset.fetchAssets(with: .video, options: options).firstObject)
        // Diagnostic branch only. Use PhotoKit + AVPlayer directly, without
        // PlaybackModel, its observers, intent state or seek queue.
        let optionsForVideo = PHVideoRequestOptions()
        optionsForVideo.version = .current
        optionsForVideo.deliveryMode = .highQualityFormat
        let loadedItem: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: optionsForVideo) { item, _ in
                continuation.resume(returning: item)
            }
        }
        let item = try XCTUnwrap(loadedItem)
        item.audioTimePitchAlgorithm = .spectral
        let player = AVPlayer(playerItem: item)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let layer = AVPlayerLayer() // Diagnostic: same visible layer, no AVPlayer attachment.
        layer.frame = controller.view.bounds
        XCTAssertGreaterThan(layer.bounds.width, 0)
        XCTAssertGreaterThan(layer.bounds.height, 0)
        controller.view.layer.addSublayer(layer)
        defer {
            player.pause(); player.replaceCurrentItem(with: nil); layer.player = nil
            window.isHidden = true; previous?.makeKey()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        player.play()
        try await ready { player.timeControlStatus == .playing && player.currentTime().seconds >= 4.25 }
        player.pause()
        let pausedPosition = player.currentTime().seconds
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(player.currentTime().seconds, pausedPosition, accuracy: 0.001)
        print("CI_RAW_PLAYER paused=\(pausedPosition) status=\(item.status.rawValue)")
        for target in [7.5, 22.5, 15.0] {
            let result = RawSeekResult()
            print("CI_RAW_PLAYER seek=\(target)")
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                print("CI_RAW_PLAYER callback=\(finished)")
                Task { @MainActor in result.finished = finished }
            }
            try await ready(seeking: true) { result.finished != nil }
            XCTAssertEqual(result.finished, true)
            XCTAssertEqual(player.currentTime().seconds, target, accuracy: 0.001)
            XCTAssertEqual(player.rate, 0)
        }
    }

    @MainActor private func ready(seeking: Bool = false, onSlowSeek: (() -> Void)? = nil, _ predicate: () -> Bool) async throws {
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(15))
        var captured = false
        while !predicate() {
            // Trigger read-only capture only for an unusually long native seek,
            // not for the intentional playback-to-4.25s precondition below.
            if seeking && !captured && ContinuousClock.now >= started.advanced(by: .seconds(2)) {
                onSlowSeek?()
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
        let performanceCheckerLoaded = (0..<_dyld_image_count()).contains { index in
            _dyld_get_image_name(index).map { String(cString: $0).contains("/libRPAC.dylib") } ?? false
        }
        print("CI_PERFORMANCE_CHECKER loaded=\(performanceCheckerLoaded)")
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
        let ratePresentation = LongGOPRatePresentation()
        let controller = UIHostingController(rootView: LongGOPPlayerHarness(model: model, ratePresentation: ratePresentation))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { model.close(); window.isHidden = true; previous?.makeKey() }
        model.load()
        // Reproduce the observed UI condition: actual playback has advanced
        // beyond four seconds before pausing. This is a media-state condition,
        // not a delay added to seeking or a replacement for the early-pause test.
        try await ready { model.player.timeControlStatus == .playing && model.player.currentTime().seconds >= 4.25 }
        model.pause()
        // The UI failure paused for about six seconds while selecting speed
        // and locating the bar. Exercise that idle-player condition here too.
        // This is a test input, never a delay in the application's seek path.
        let pausedPosition = model.player.currentTime().seconds
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(model.player.currentTime().seconds, pausedPosition, accuracy: 0.001)
        XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
        // Every failing UI path selected speed through the production popover;
        // directly setting a model property did not exercise its presentation.
        ratePresentation.visible = true
        try await ready {
            guard let presented = controller.presentedViewController else { return false }
            return !presented.isBeingPresented && presented.view.window != nil
        }
        let menu = try XCTUnwrap(controller.presentedViewController)
        model.setRate(0.25)
        ratePresentation.visible = false
        // A cleared presentation relationship alone does not prove that the
        // outgoing popover has left the window. Complete this test setup at
        // actual view detachment, without a fixed post-dismissal delay.
        try await ready { controller.presentedViewController == nil && menu.view.window == nil }
        print("CI_NATIVE_MENU dismissed=true detached=\(menu.view.window == nil) transition=\(controller.transitionCoordinator != nil)")
        let bar = try XCTUnwrap(findBar(in: controller.view))
        XCTAssertGreaterThan(bar.bounds.width, 0)
        let surface = try XCTUnwrap(findSurface(in: controller.view))
        XCTAssertTrue(surface.playerLayer.player === model.player)
        describeOutput(surface, model: model, phase: "before-seek")
        print("LongGOP production view pause at \(model.player.currentTime().seconds)")
        // Also cover overlapping committed requests after actual playback,
        // rather than testing overlap only at the very beginning of the clip.
        for target in [7.5, 22.5, 15.0] {
            let x = bar.bounds.width * CGFloat(target / model.duration)
            XCTAssertTrue(bar.start(at: x)); bar.finish(at: x)
        }
        try await ready(seeking: true, onSlowSeek: {
            self.describeOutput(surface, model: model, phase: "waiting-seek")
        }) { !model.isSeeking }
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

    @MainActor private func findSurface(in view: UIView) -> VideoGestureView? {
        if let surface = view as? VideoGestureView { return surface }
        return view.subviews.lazy.compactMap { self.findSurface(in: $0) }.first
    }

    @MainActor private func describeOutput(_ surface: VideoGestureView, model: PlaybackModel, phase: String) {
        print("CI_VIDEO_OUTPUT phase=\(phase) app=\(UIApplication.shared.applicationState.rawValue) scene=\(surface.window?.windowScene?.activationState.rawValue ?? -1) key=\(surface.window?.isKeyWindow ?? false) measured=\(model.player.currentTime().seconds) requested=\(model.position) seeking=\(model.isSeeking) ready=\(surface.playerLayer.isReadyForDisplay) videoRect=\(surface.playerLayer.videoRect)")
        var view: UIView? = surface
        while let current = view {
            print("CI_VIDEO_VIEW type=\(type(of: current)) hidden=\(current.isHidden) alpha=\(current.alpha) bounds=\(current.bounds) window=\(current.window != nil)")
            view = current.superview
        }
        var layer: CALayer? = surface.playerLayer
        while let current = layer {
            print("CI_VIDEO_LAYER type=\(type(of: current)) hidden=\(current.isHidden) opacity=\(current.opacity) bounds=\(current.bounds) speed=\(current.speed) timeOffset=\(current.timeOffset) presentationOpacity=\(current.presentation()?.opacity ?? -1) animations=\(current.animationKeys() ?? [])")
            layer = current.superlayer
        }
    }
}

@MainActor private final class LongGOPRatePresentation: ObservableObject {
    @Published var visible = false
}

@MainActor private final class RawSeekResult {
    var finished: Bool?
}

@MainActor private struct LongGOPPlayerHarness: View {
    @ObservedObject var model: PlaybackModel
    @ObservedObject var ratePresentation: LongGOPRatePresentation
    var body: some View {
        ZStack {
            PlayerSurface(model: model, fullscreen: true).ignoresSafeArea()
            Image(systemName: "play.fill").font(.system(size: 34)).frame(width: 80, height: 80).mediaGlass()
            VStack {
                Spacer()
                PlaybackTransportControls(state: PlaybackTransportState(
                    position: model.displayedPosition, duration: model.duration, isReady: model.isReady,
                    canPlaySlow: model.canPlaySlow, showsPause: model.showsPauseControl,
                    selectedRate: model.selectedRate, stateText: model.stateText,
                    cancellationID: model.gestureCancellationID), fullscreen: true,
                    ratePresentation: $ratePresentation.visible,
                    actions: PlaybackTransportActions(begin: model.beginScrubbing, change: model.scrub,
                        commit: model.endScrubbing, cancel: model.cancelScrubbing, setRate: model.setRate))
            }.padding(12)
        }.foregroundStyle(.white).tint(.white).background(.black)
    }
}
