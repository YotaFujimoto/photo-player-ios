import XCTest
import SwiftUI
@testable import PhotoPlayer

final class SeekFeedbackStyleTests: XCTestCase {
    func testFeedbackNeverCoversPlayButtonAndSymbolsFitEveryPicture() {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)] {
            let canvas = CGRect(origin: .zero, size: size)
            let play = CGRect(x: canvas.midX - 40, y: canvas.midY - 40, width: 80, height: 80)
            for ratio in [0.3, 0.5625, 1, 1.7778, 2.4, 8, 16] {
                let video = VideoGeometry.fitted(CGSize(width: 1000 * ratio, height: 1000), in: canvas)
                for visible in [false, true] {
                    let hud = SeekFeedbackStyle.horizontalFrame(video: video, canvas: canvas, playButton: visible ? play : nil)
                    XCTAssertTrue(canvas.contains(hud))
                    XCTAssertEqual(hud.midX, video.midX, accuracy: 0.001)
                    if visible { XCTAssertLessThanOrEqual(hud.maxY, play.minY - 10) }
                    if video.height < 80 && visible { XCTAssertLessThan(hud.minY, video.minY, "Use existing letterbox, not a smaller picture") }
                }
                for forward in [false, true] {
                    let symbol = SeekFeedbackStyle.skipFrame(in: video, forward: forward)
                    XCTAssertTrue(video.contains(symbol)); XCTAssertLessThan(symbol.height, play.height)
                    XCTAssertEqual(symbol.midY, video.midY)
                }
            }
        }
    }
    func testCompactClockAndUniformOneDecimalDelta() {
        XCTAssertEqual(SeekFeedbackStyle.clock(5), "00:05")
        XCTAssertEqual(SeekFeedbackStyle.clock(65), "01:05")
        XCTAssertEqual(SeekFeedbackStyle.clock(3605), "1:00:05")
        XCTAssertEqual(SeekFeedbackStyle.difference(10), "+10.0s")
        XCTAssertEqual(SeekFeedbackStyle.difference(-1.24), "−1.2s")
        XCTAssertEqual(SeekFeedbackStyle.difference(0), "+0.0s")
        XCTAssertEqual(SeekFeedbackStyle.difference(.nan), "+0.0s")
    }

    @MainActor func testStableFeedbackSizeAndRenderOnBrightAndDarkFrames() async throws {
        var sizes: [CGSize] = []
        for target in [1.0, 65, 3605, 36005] {
            let content = SeekFeedbackOverlay(preview: SeekPreview(source: .horizontal, origin: 0, target: target), skip: nil, pictureSize: CGSize(width:390,height:200))
            let host = UIHostingController(rootView: content)
            sizes.append(host.sizeThatFits(in: CGSize(width: 390, height: 200)))
        }
        for size in sizes {
            XCTAssertEqual(size.width, sizes[0].width, accuracy: 0.5)
            XCTAssertEqual(size.height, sizes[0].height, accuracy: 0.5)
        }
        // Hold preview state in this native view test, not a longer product HUD
        // lifetime. XCTest's post-gesture idle wait can exceed its 450ms lifetime.
        // Render the real overlay and button anchor on a live hosting window.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKey() }
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            for bright in [false, true] {
                let record = FeedbackLayoutRecord()
                let content = GeometryReader { geometry in
                    ZStack {
                        (bright ? Color.white : Color.black)
                        Image(systemName: "play.fill").font(.system(size: 34, weight: .semibold))
                            .frame(width: 80, height: 80).mediaGlass()
                            .anchorPreference(key: PlayerButtonBoundsKey.self, value: .bounds) { $0 }
                            .offset(x: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                                    y: (geometry.safeAreaInsets.bottom - geometry.safeAreaInsets.top) / 2)
                    }.overlayPreferenceValue(PlayerButtonBoundsKey.self) { anchor in
                        GeometryReader { proxy in
                            let play = anchor.map { proxy[$0] }
                            SeekFeedbackOverlay(preview: SeekPreview(source: .horizontal, origin: 63.5, target: 75.8),
                                skip: SkipFeedback(forward: true, origin: 10, target: 20, duration: 30),
                                pictureSize: CGSize(width: 320, height: 180), playButtonFrame: play)
                                .onAppear { record.play = play }
                                .onChange(of: play) { _, value in record.play = value }
                        }
                    }
                }.foregroundStyle(.white).ignoresSafeArea()
                let host = UIHostingController(rootView: content)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host; window.makeKeyAndVisible()
                host.view.frame = window.bounds; host.view.layoutIfNeeded()
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while record.play == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
                let play = try XCTUnwrap(record.play)
                XCTAssertEqual(play.size, CGSize(width: 80, height: 80))
                let canvas = CGRect(origin: .zero, size: size)
                let video = VideoGeometry.fitted(CGSize(width: 320, height: 180), in: canvas)
                let hud = SeekFeedbackStyle.horizontalFrame(video: video, canvas: canvas, playButton: play)
                XCTAssertLessThanOrEqual(hud.maxY, play.minY - 8)
                XCTAssertTrue(canvas.contains(hud))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "feedback-play-anchor-\(Int(size.width))-\(bright ? "bright" : "dark")"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}

@MainActor private final class FeedbackLayoutRecord { var play: CGRect? }
