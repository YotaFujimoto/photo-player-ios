import XCTest
import UIKit

final class VideoSelectionTests: XCTestCase {
    @MainActor func testRow1SelectionBounds() { checkRow(1) }
    @MainActor func testRow2SelectionBounds() { checkRow(2) }
    @MainActor func testRow3SelectionBounds() { checkRow(3) }
    @MainActor func testRow4SelectionBounds() { checkRow(4) }
    @MainActor func testRow5SelectionBounds() { checkRow(5) }
    @MainActor func testRow6SelectionBounds() { checkRow(6) }

    @MainActor
    private func launch(delayed: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--selection-diagnostics"] + (delayed ? ["--delay-thumbnails"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    private func checkRow(_ row: Int) {
        let app = launch()
        for number in (row * 2 - 1)...(row * 2) {
            let card = reveal(number, in: app)
            let dimensions = card.value as! String
            XCTAssertTrue(card.images["videoThumbnail"].waitForExistence(timeout: 15))
            verifyThumbnail(card, dimensions: dimensions)
            let other = app.buttons["videoCard.\(number % 2 == 0 ? number - 1 : number + 1)"]
            XCTAssertFalse(card.frame.intersects(other.frame), "Adjacent cells must not overlap")
            attach("selection-row-\(row)-cell-\(number)")
            // The image bottom and caption bottom are distinct targets. Use physical
            // screen coordinates, not Button.tap(), which can choose a safe hit point.
            for point in ["top", "center", "image-bottom", "bottom"] {
                XCTContext.runActivity(named: "Cell \(number), \(dimensions), \(point)") { _ in
                    let visible = reveal(number, in: app)
                    let rect = visible.frame
                    let y: CGFloat = point == "top" ? 3 : point == "center" ? rect.height / 2 :
                        point == "image-bottom" ? 107 : rect.height - 3
                    let origin = app.coordinate(withNormalizedOffset: .zero)
                    origin.withOffset(CGVector(dx: rect.midX, dy: rect.minY + y)).tap()
                    verifySelection(number, dimensions: dimensions, in: app)
                    if point == "image-bottom" { attach("selected-\(number)-image-bottom") }
                    app.buttons["closePlayer"].tap()
                    XCTAssertTrue(visible.waitForExistence(timeout: 10))
                }
            }
        }
    }

    @MainActor
    func testScrollReloadAndPendingThumbnailsKeepAssetIdentity() {
        let app = launch(delayed: true)
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp(velocity: .fast)
        scroll.swipeDown(velocity: .fast)
        scroll.swipeUp(velocity: .fast)
        let last = reveal(12, in: app)
        app.buttons["refreshLibrary"].tap()
        XCTAssertTrue(last.images["thumbnailPlaceholder"].waitForExistence(timeout: 3))
        let dimensions = last.value as! String
        let rect = last.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: rect.midX, dy: rect.minY + 107)).tap()
        verifySelection(12, dimensions: dimensions, in: app)
        app.buttons["closePlayer"].tap()
        XCTAssertTrue(last.images["videoThumbnail"].waitForExistence(timeout: 15))
        verifyThumbnail(last, dimensions: dimensions)
        let first = reveal(1, in: app)
        XCTAssertTrue(first.images["videoThumbnail"].waitForExistence(timeout: 15))
        let firstDimensions = first.value as! String
        first.tap()
        verifySelection(1, dimensions: firstDimensions, in: app)
        app.buttons["closePlayer"].tap()
        attach("selection-after-scroll-reload")
    }

    @MainActor
    private func reveal(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        let card = app.buttons["videoCard.\(number)"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let viewport = scroll.frame.insetBy(dx: 0, dy: 5)
            if card.exists {
                let rect = card.frame
                if viewport.contains(rect), card.isHittable { return card }
                if rect.minY < viewport.minY { scroll.swipeDown(); continue }
            }
            scroll.swipeUp()
        }
        XCTFail("Cell \(number) was not fully visible after scrolling")
        return card
    }

    @MainActor
    private func verifySelection(_ number: Int, dimensions: String, in app: XCUIApplication) {
        let selected = app.staticTexts["selectedVideo"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "Tap must open a player")
        XCTAssertEqual(selected.label, "動画 \(number)", "The tapped cell must select its own PHAsset")
        XCTAssertEqual(selected.value as? String, dimensions)
        let loaded = app.staticTexts["loadedVideoSize"]
        let decoded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", dimensions), object: loaded)
        XCTAssertEqual(XCTWaiter.wait(for: [decoded], timeout: 15), .completed,
                       "The decoded AVPlayerItem must match the displayed video's dimensions")
    }

    @MainActor
    private func verifyThumbnail(_ card: XCUIElement, dimensions: String) {
        // Colors/dimensions come from the independent FFmpeg fixtures, not app labels.
        let colors: [String: [Double]] = [
            "180x320": [1, 0, 0], "202x202": [0, 1, 0], "340x180": [0, 0, 1],
            "182x340": [1, 1, 0], "204x204": [1, 0, 1], "360x180": [0, 1, 1],
            "184x360": [1, 0.647, 0], "206x206": [0.502, 0, 0.502], "380x180": [0, 0.502, 0.502],
            "186x380": [1, 0.753, 0.796], "208x208": [0.502, 0.502, 0.502]
        ]
        guard let expected = colors[dimensions] else {
            XCTAssertEqual(dimensions, "320x180") // Original moving test pattern.
            return
        }
        let source = card.images["videoThumbnail"].screenshot().image.cgImage!
        // Sample the middle, away from the duration badge and rounded corners.
        let crop = source.cropping(to: CGRect(x: CGFloat(source.width) / 3, y: CGFloat(source.height) / 3,
                                              width: CGFloat(source.width) / 3, height: CGFloat(source.height) / 3))!
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        for channel in 0..<3 {
            XCTAssertEqual(Double(rgba[channel]) / 255, expected[channel], accuracy: 0.15,
                           "Visible thumbnail must belong to the labeled asset \(dimensions)")
        }
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
