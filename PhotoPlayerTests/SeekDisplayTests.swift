import XCTest
import Photos
import AVFoundation
import UIKit
@testable import PhotoPlayer

/// A simulator screen recording observes presentation, separately from seek
/// callbacks. Green marker brackets only the interval with a loaded picture.
final class SeekDisplayTests: XCTestCase {
    @MainActor func testVisiblePictureAcrossAllSeekSources() async throws {
        let assets = PHAsset.fetchAssets(with: .video, options: nil)
        let asset = try XCTUnwrap(assets.objects(at: IndexSet(integersIn: 0..<assets.count))
            .first { $0.pixelWidth == 320 && $0.pixelHeight == 180 })
        let model = PlaybackModel(asset: asset)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController(); window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.backgroundColor = .black
        let picture = VideoGestureView(frame: CGRect(x: 20, y: 160, width: 320, height: 180))
        controller.view.addSubview(picture); model.connectVideoOutput(picture.playerLayer)
        let marker = UIView(frame: CGRect(x: 20, y: 120, width: 32, height: 20))
        marker.backgroundColor = .black; controller.view.addSubview(marker)
        let bar = SeekBarControl(frame: CGRect(x: 20, y: 360, width: 320, height: 44))
        controller.view.addSubview(bar)
        bar.onBegin = model.beginScrubbing; bar.onChange = model.scrub
        bar.onCommit = model.endScrubbing; bar.onCancel = model.cancelScrubbing
        defer { marker.backgroundColor = .black; model.close(); window.isHidden = true; previous?.makeKey() }
        model.load(); try await ready { model.player.timeControlStatus == .playing && picture.playerLayer.isReadyForDisplay }
        model.pause(); model.setRate(0.25)
        _ = image(picture)
        print("CI_DISPLAY_CANVAS \(Int(window.bounds.width)) \(Int(window.bounds.height))")
        marker.backgroundColor = .green
        bar.configure(position: model.position, duration: model.duration, enabled: true, cancellationID: 0)
        for target in [2.0, 14, 26, 7] {
            XCTAssertTrue(bar.start(at: 320 * target / model.duration))
            try await ready { !model.isSeeking && abs(model.player.currentTime().seconds-target) < 0.151 }
            // Keep the finger down while checking the main picture, not just time.
            XCTAssertTrue(bar.interacting); XCTAssertEqual(model.player.rate, 0)
            let shot = image(picture)
            let attachment = XCTAttachment(image: shot); attachment.name = "display-held-\(target)"; attachment.lifetime = .keepAlways; add(attachment)
            bar.move(to: 320 * (target + 1) / model.duration)
            try await ready { !model.isSeeking && abs(model.player.currentTime().seconds-target-1) < 0.151 }
            bar.finish(at: 320 * (target + 1) / model.duration)
            try await ready { !model.isSeeking && !model.isBarSeeking }
            for forward in [true, false] {
                model.skip(forward: forward); try await ready { !model.isSeeking }
                _ = image(picture)
            }
            XCTAssertTrue(model.beginHorizontalSeek())
            model.updateHorizontalSeek(translation: 16, width: 320); model.endHorizontalSeek()
            try await ready { !model.isSeeking }
            _ = image(picture)
            XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.player.rate, 0)
            XCTAssertEqual(model.selectedRate, 0.25); XCTAssertNil(model.errorMessage)
        }
        // Recording continues across play/seek/resume, then the marker ends
        // before deliberate teardown; teardown's empty layer is not a flash.
        model.togglePlayback(); try await ready { model.player.timeControlStatus == .playing }
        model.skip(forward: false); try await ready { !model.isSeeking && model.player.rate == 0.25 }
        _ = image(picture)
        marker.backgroundColor = .black
        _ = image(controller.view)
    }
    @MainActor private func image(_ view: UIView) -> UIImage {
        UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
    }
    @MainActor private func ready(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() {
            guard ContinuousClock.now < deadline else { XCTFail("Seek display state exceeded 15 seconds"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
