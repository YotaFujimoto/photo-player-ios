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

    @MainActor func testStableFeedbackSizeAndRenderOnBrightAndDarkFrames() throws {
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
        for bright in [false, true] {
            let content = VStack(spacing: 0) {
                SeekFeedbackOverlay(preview: SeekPreview(source: .horizontal, origin: 63.5, target: 75.8), skip: nil, pictureSize: CGSize(width:390,height:100))
                    .frame(width: 390, height: 100)
                SeekFeedbackOverlay(preview: nil, skip: SkipFeedback(forward: true, origin: 10, target: 20, duration: 30), pictureSize: CGSize(width:390,height:100))
                    .frame(width: 390, height: 100)
            }.background(bright ? Color.white : Color.black)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: 390, height: 200))
            let attachment = XCTAttachment(image: image)
            attachment.name = bright ? "feedback-on-bright-frame" : "feedback-on-dark-frame"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
