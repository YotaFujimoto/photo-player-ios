import XCTest
import Photos
import AVFoundation
import UIKit
@testable import PhotoPlayer

/// Uses the production control and the actual visible player layer. A changing
/// clock alone cannot satisfy the pixel comparison while the control is held.
final class LiveScrubbingTests: XCTestCase {
    @MainActor func testMainPictureChangesBeforeReleaseAndLatestTargetWins() async throws {
        let assets = PHAsset.fetchAssets(with: .video, options: nil)
        let asset = try XCTUnwrap(assets.objects(at: IndexSet(integersIn: 0..<assets.count))
            .first { $0.pixelWidth == 320 && $0.pixelHeight == 180 })
        let model = PlaybackModel(asset: asset)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController(); window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.backgroundColor = .black
        let picture = VideoGestureView(frame: CGRect(x: 20, y: 160, width: 320, height: 180))
        controller.view.addSubview(picture); model.connectVideoOutput(picture.playerLayer)
        let bar = SeekBarControl(frame: CGRect(x: 20, y: 360, width: 320, height: 44))
        controller.view.addSubview(bar)
        bar.onBegin = model.beginScrubbing; bar.onChange = model.scrub
        bar.onCommit = model.endScrubbing; bar.onCancel = model.cancelScrubbing
        defer { bar.cancelInteraction(); model.close(); window.isHidden = true; previous?.makeKey() }
        model.load(); try await ready { model.player.timeControlStatus == .playing }
        model.pause(); model.setRate(0.25)
        bar.configure(position: model.position, duration: model.duration, enabled: true, cancellationID: 0)
        bar.layoutIfNeeded()
        XCTAssertTrue(bar.start(at: 320 * 0.2))
        try await ready { !model.isSeeking && abs(model.player.currentTime().seconds - 6) < 0.151 && picture.playerLayer.isReadyForDisplay }
        let first = pixels(picture)
        XCTAssertGreaterThan(first.map(Int.init).reduce(0, +), 5000, "Main image must contain decoded video, not black")
        let firstImage = image(picture)
        bar.move(to: 320 * 0.7)
        try await ready { !model.isSeeking && abs(model.player.currentTime().seconds - 21) < 0.151 && picture.playerLayer.isReadyForDisplay && difference(first, self.pixels(picture)) > 4 }
        XCTAssertTrue(bar.interacting); XCTAssertTrue(model.isBarSeeking)
        XCTAssertEqual(model.player.rate, 0); XCTAssertEqual(model.selectedRate, 0.25)
        for (name, shot) in [("held-main-video-6s", firstImage), ("held-main-video-21s", image(picture))] {
            let attachment = XCTAttachment(image: shot); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        for index in 0..<200 { bar.move(to: index.isMultiple(of: 2) ? 10 : 310) }
        bar.finish(at: 160)
        XCTAssertTrue(model.isBarSeeking)
        try await ready { !model.isSeeking && !model.isBarSeeking }
        XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.001)
        XCTAssertEqual(model.player.rate, 0); XCTAssertFalse(model.wantsPlayback)
        XCTAssertNil(model.errorMessage)
        // A decoded preview must also roll back after actual control cancellation.
        XCTAssertTrue(bar.start(at: 270))
        try await ready { !model.isSeeking && model.player.currentTime().seconds > 25 }
        bar.cancelInteraction(); bar.finish(at: 300)
        try await ready { !model.isSeeking }
        XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.001)
        XCTAssertFalse(model.isBarSeeking); XCTAssertEqual(model.player.rate, 0)
        // Close with a scheduled preview and ignore its late release/callback.
        XCTAssertTrue(bar.start(at: 250)); model.close(); bar.finish(at: 200)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(model.player.currentItem); XCTAssertFalse(model.isBarSeeking)
        XCTAssertFalse(model.wantsPlayback); XCTAssertFalse(model.isSeeking)
    }

    @MainActor private func image(_ view: UIView) -> UIImage {
        UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
    }
    @MainActor private func pixels(_ view: UIView) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32 * 18 * 4)
        let cg = image(view).cgImage!
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 32, height: 18, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 32, height: 18))
        }
        return bytes.enumerated().filter { $0.offset % 4 != 3 }.map(\.element)
    }
    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }
    @MainActor private func ready(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() {
            guard ContinuousClock.now < deadline else { XCTFail("Live main-picture scrub exceeded 15 seconds"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
