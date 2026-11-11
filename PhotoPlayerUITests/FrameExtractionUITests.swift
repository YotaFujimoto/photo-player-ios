import XCTest
import UIKit

final class FrameExtractionUITests: XCTestCase {
    @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func expect(_ element: XCUIElement, _ predicate: NSPredicate) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
    }
    @MainActor private func value(_ app: XCUIApplication, _ id: String, _ expected: String) {
        expect(element(app,id), NSPredicate(format:"value == %@",expected))
    }
    @MainActor private func open() -> XCUIApplication {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication.photoPlayerForTesting()
        app.launch()
        let card=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'videoCard.' AND value == '160x96'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:20)); card.tap()
        value(app,"videoSurface","Playing")
        app.playerButton("playPause").tap(); value(app,"videoSurface","Paused")
        app.playerButton("rateMenu").tap(); app.buttons.matching(identifier:"0.25×").firstMatch.tap()
        element(app,"seekSlider").coordinate(withNormalizedOffset:CGVector(dx:0.01,dy:0.5)).tap()
        value(app,"videoSurface","Paused")
        return app
    }
    @MainActor private func enter(_ app: XCUIApplication) {
        app.playerButton("extractFrames").tap()
        expect(app.buttons.matching(identifier:"saveFrames").firstMatch,NSPredicate(format:"enabled == true"))
        value(app,"framePreview","Frame 0")
    }
    @MainActor private func move(_ app: XCUIApplication, index: Int) {
        let bar=element(app,"frameTimeline")
        // The visible rail has a 10 pt inset and an inclusive 0...90 frame window.
        let x=(10 + CGFloat(index)/90*(bar.frame.width-20))/bar.frame.width
        bar.coordinate(withNormalizedOffset:CGVector(dx:x,dy:0.5)).tap()
        value(app,"framePreview","Frame \(index)")
    }
    @MainActor private func capture(_ name: String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testFixedWindowIndependentCursorAndEndpointButtons() {
        let app=open(); enter(app)
        let timeline=element(app,"frameTimeline"), initial=timeline.frame
        value(app,"frameTimeline","P=0 S=0 E=90 W=0...90")
        move(app,index:30); app.buttons.matching(identifier:"setFrameStart").firstMatch.tap()
        move(app,index:60); app.buttons.matching(identifier:"setFrameEnd").firstMatch.tap()
        move(app,index:0)
        value(app,"frameTimeline","P=0 S=30 E=60 W=0...90")
        XCTAssertFalse(app.buttons.matching(identifier:"setFrameEnd").firstMatch.isEnabled)
        move(app,index:90)
        value(app,"frameTimeline","P=90 S=30 E=60 W=0...90")
        XCTAssertFalse(app.buttons.matching(identifier:"setFrameStart").firstMatch.isEnabled)
        XCTAssertEqual(timeline.frame,initial)
        move(app,index:30); app.buttons.matching(identifier:"setFrameEnd").firstMatch.tap()
        XCTAssertEqual(element(app,"frameSummary").label,"1 frame")
        value(app,"frameTimeline","P=30 S=30 E=30 W=0...90")
        capture("frame-equal-endpoints")
        move(app,index:90); app.buttons.matching(identifier:"setFrameEnd").firstMatch.tap()
        move(app,index:0); app.buttons.matching(identifier:"setFrameStart").firstMatch.tap()
        value(app,"frameTimeline","P=0 S=0 E=90 W=0...90")
        app.buttons.matching(identifier:"cancelFrames").firstMatch.tap()
        value(app,"videoSurface","Paused")
        XCTAssertEqual(app.playerButton("rateMenu").value as? String,"0.25×")
    }

    @MainActor func testEntryPixelsFrameStepsSwipeAndNormalGestureRestoration() throws {
        let app=open()
        element(app,"seekSlider").coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.5)).tap()
        value(app,"videoSurface","Paused")
        let before=try numberInScreenshot(element(app,"videoSurface").frame)
        XCTAssertGreaterThan(before,0)
        enter(app)
        let preview=element(app,"framePreview")
        XCTAssertEqual(try numberInScreenshot(preview.frame),before,"Entry must preserve the actual visible frame")
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.5)).doubleTap()
        value(app,"framePreview","Frame 1")
        XCTAssertEqual(try numberInScreenshot(preview.frame),before+1)
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.5)).doubleTap()
        value(app,"framePreview","Frame 0")
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5)).press(forDuration:0.05,
            thenDragTo:preview.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0.2)
        value(app,"framePreview","Frame 6")
        XCTAssertEqual(try numberInScreenshot(preview.frame),before+6)
        preview.press(forDuration:1)
        value(app,"framePreview","Frame 6")
        XCTAssertFalse(element(app,"temporaryRate").exists)
        XCTAssertFalse(element(app,"skipFeedback").exists)
        capture("frame-portrait-preview")
        app.buttons.matching(identifier:"cancelFrames").firstMatch.tap()
        value(app,"videoSurface","Paused")
        XCTAssertEqual(try numberInScreenshot(element(app,"videoSurface").frame),before+6)
        XCTAssertEqual(app.playerButton("rateMenu").value as? String,"0.25×")
        let video=element(app,"videoSurface")
        video.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.5)).doubleTap()
        let restoredSeconds=Int(Double(before+6)/30)
        expect(element(app,"playbackPosition"),NSPredicate(format:"label == %@",String(format:"0:%02d",restoredSeconds+10)))
        value(app,"videoSurface","Paused")
        video.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.5)).doubleTap()
        expect(element(app,"playbackPosition"),NSPredicate(format:"label == %@",String(format:"0:%02d",restoredSeconds)))
    }

    @MainActor func testLandscapeControlsStayVisibleAndDoneSavesThenReturnsPaused() {
        let app=open()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        enter(app)
        XCUIDevice.shared.orientation = .landscapeRight
        let preview=element(app,"framePreview")
        expect(preview,NSPredicate { object,_ in
            guard let item=object as? XCUIElement else { return false }
            return item.frame.width > item.frame.height
        })
        let frame=preview.frame, screen=app.windows.firstMatch.frame
        XCTAssertEqual(frame.width,screen.width,accuracy:1)
        XCTAssertEqual(frame.height,screen.height,accuracy:1)
        for id in ["cancelFrames","saveFrames","setFrameStart","setFrameEnd","frameTimeline"] {
            let control=element(app,id)
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(frame.insetBy(dx:10,dy:10).contains(control.frame))
            XCTAssertGreaterThanOrEqual(control.frame.height,44)
        }
        // A continuous four-second contact must neither hide controls nor play.
        preview.press(forDuration:4)
        value(app,"framePreview","Frame 0")
        XCTAssertTrue(app.buttons.matching(identifier:"saveFrames").firstMatch.isHittable)
        move(app,index:30)
        XCTAssertEqual(preview.frame,frame)
        capture("frame-landscape-preview")
        app.buttons.matching(identifier:"saveFrames").firstMatch.tap()
        let success=element(app,"frameSaveSuccess")
        XCTAssertTrue(success.waitForExistence(timeout:30))
        XCTAssertEqual(success.label,"Saved 10 photos.")
        let noticeFrame=success.frame
        XCTAssertGreaterThan(noticeFrame.height,0)
        XCTAssertFalse(noticeFrame.intersects(app.playerButton("closePlayer").frame))
        XCTAssertFalse(noticeFrame.intersects(app.playerButton("extractFrames").frame))
        value(app,"videoSurface","Paused")
        XCTAssertEqual(app.playerButton("rateMenu").value as? String,"0.25×")
        XCTAssertFalse(element(app,"frameTimeline").exists)
        capture("frame-save-returned-paused")
        // Enter on one side, leave on the other, then rotate 180 degrees after
        // auto-hide. The normal player must not retain the old entry orientation.
        let play=app.buttons.matching(identifier:"playPause").firstMatch
        play.tap(); value(app,"videoSurface","Playing")
        expect(play,NSPredicate(format:"exists == false"))
        XCUIDevice.shared.orientation = .landscapeLeft
        expect(play,NSPredicate(format:"exists == true"))
        play.tap(); value(app,"videoSurface","Paused")
    }

    /// Decode the generated video's eight binary blocks from displayed pixels,
    /// independently of the app's requested timestamp and accessibility value.
    @MainActor private func numberInScreenshot(_ surface: CGRect) throws -> Int {
        let screenshot=XCUIScreen.main.screenshot().image
        let image=try XCTUnwrap(screenshot.cgImage)
        let scale=CGFloat(image.width)/screenshot.size.width
        let fit=min(surface.width/160,surface.height/96)
        let video=CGRect(x:surface.midX-80*fit,y:surface.midY-48*fit,width:160*fit,height:96*fit)
        var pixels=[UInt8](repeating:0,count:image.width*image.height*4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        var number=0
        for bit in 0..<8 {
            let x=Int((video.minX+CGFloat(bit*20+10)*fit)*scale), y=Int((video.minY+16*fit)*scale)
            XCTAssertTrue((0..<image.width).contains(x) && (0..<image.height).contains(y))
            if pixels[(y*image.width+x)*4] > 127 { number |= 1 << bit }
        }
        return number
    }
}
