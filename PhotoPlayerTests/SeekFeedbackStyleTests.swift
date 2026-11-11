import XCTest
import SwiftUI
@testable import PhotoPlayer

final class SeekFeedbackStyleTests: XCTestCase {
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
