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
    func testSelectionBoundsWithDiagnosticsOff() {
        let app = launch()
        app.buttons["selectionDiagnostics"].tap()
        for number in 2...4 {
            let card = reveal(number, in: app)
            let dimensions = card.value as! String
            XCTAssertTrue(card.images["videoThumbnail"].waitForExistence(timeout: 15))
            verifyThumbnail(card, dimensions: dimensions)
            for bottom in [false, true] {
                let rect = reveal(number, in: app).frame
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                    dx: rect.midX, dy: bottom ? rect.maxY - 3 : rect.minY + 3)).tap()
                let selected = app.staticTexts["selectedVideo"]
                XCTAssertTrue(selected.waitForExistence(timeout: 10))
                XCTAssertEqual(selected.label, "再生")
                XCTAssertEqual(selected.value as? String, dimensions)
                XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 15))
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"),
                                                     object: app.buttons["playPause"])
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
                app.buttons["closePlayer"].tap()
            }
        }
        attach("selection-diagnostics-off")
    }

    @MainActor
    private func reveal(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        let card = app.buttons["videoCard.\(number)"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let viewport = scroll.frame.insetBy(dx: 0, dy: 5)
            if card.exists {
                let rect = card.frame
                if rect.height > 0, viewport.contains(rect), card.isHittable { return card }
                if rect.height > 0 && rect.minY < viewport.minY { scroll.swipeDown(); continue }
            }
            if number == 1 { scroll.swipeDown() } else { scroll.swipeUp() }
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
        guard colors[dimensions] != nil else {
            XCTAssertEqual(dimensions, "320x180") // Original moving test pattern.
            return
        }
        // Sample the visible cell, not the scaled image's accessibility bounds.
        let source = card.screenshot().image.cgImage!
        let scale = CGFloat(source.height) / card.frame.height
        let crop = source.cropping(to: CGRect(x: CGFloat(source.width) / 3, y: 35 * scale,
                                              width: CGFloat(source.width) / 3, height: 30 * scale))!
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        // H.264 YUV decoding/display conversion changes RGB channel values (the
        // green fixture renders as 63,251,0). Classify against ALL fixture colors
        // instead of requiring raw source RGB; wrong assets still fail identity.
        let sampled = rgba.prefix(3).map { Double($0) / 255 }
        let ranked = colors.map { entry in
            (dimensions: entry.key, distance: zip(sampled, entry.value)
                .reduce(0.0) { $0 + pow($1.0 - $1.1, 2) }.squareRoot())
        }.sorted { $0.distance < $1.distance }
        XCTAssertLessThan(ranked[0].distance, 0.35, "Thumbnail must contain a fixture color")
        XCTAssertEqual(ranked[0].dimensions, dimensions,
                       "Visible thumbnail must belong to the labeled asset \(dimensions)")
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
