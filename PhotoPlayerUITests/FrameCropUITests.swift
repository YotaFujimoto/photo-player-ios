import XCTest
import UIKit

final class FrameCropUITests: XCTestCase {
    @MainActor private func item(_ app:XCUIApplication,_ id:String)->XCUIElement { app.descendants(matching:.any).matching(identifier:id).firstMatch }
    @MainActor private func expect(_ element:XCUIElement,_ format:String,_ value:String) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:format,value),object:element)],timeout:15),.completed)
    }
    @MainActor private func open()->XCUIApplication {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication.photoPlayerForTesting(); app.launchArguments=["--verify-crop-edges"]; app.launch()
        let card=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'videoCard.' AND value == '160x96'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:20)); card.tap()
        expect(item(app,"videoSurface"),"value == %@","Playing")
        app.playerButton("playPause").tap(); expect(item(app,"videoSurface"),"value == %@","Paused")
        app.playerButton("extractFrames").tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:app.buttons["saveFrames"])],timeout:15),.completed)
        return app
    }
    @MainActor private func picture(_ preview:XCUIElement)->CGRect {
        let r=preview.frame, scale=min(r.width/160,r.height/96)
        return CGRect(x:r.midX-80*scale,y:r.midY-48*scale,width:160*scale,height:96*scale)
    }
    @MainActor private func drag(_ app:XCUIApplication,from:CGPoint,to:CGPoint) {
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:from.x,dy:from.y)).press(forDuration:0.05,
            thenDragTo:app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:to.x,dy:to.y)),withVelocity:.slow,thenHoldForDuration:0)
    }
    @MainActor private func checkHidden(_ app:XCUIApplication) {
        for id in ["cancelFrames","saveFrames","frameSummary","framePosition","frameTimeline","setFrameStart","setFrameEnd","resetCrop"] {
            XCTAssertFalse(item(app,id).exists,"Hidden control must leave accessibility and hit-testing: \(id)")
        }
        XCTAssertFalse(app.staticTexts["Loading frame…"].exists)
    }
    @MainActor private func capture(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot()); a.name=name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor private func finish(_ app:XCUIApplication) {
        app.playerButton("closePlayer").tap()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout:10))
        XCUIDevice.shared.orientation = .portrait; app.terminate(); XCTAssertEqual(app.state,.notRunning)
    }
    @MainActor func testPortraitCropGesturesRelativeWindowResetAndCancel() {
        let app=open(), preview=item(app,"framePreview")
        let canvas=preview.frame, timeline=item(app,"frameTimeline"), initialRange=timeline.value as! String
        XCTAssertEqual(item(app,"frameWindowStart").label,"0:00")
        XCTAssertEqual(item(app,"frameWindowEnd").label,"0:03")
        XCTAssertLessThan(app.buttons["setFrameStart"].frame.maxY,timeline.frame.minY)
        let top=[app.buttons["cancelFrames"].frame,item(app,"frameSummary").frame,app.buttons["saveFrames"].frame]
        XCTAssertLessThan(top[0].maxX,top[1].minX); XCTAssertLessThan(top[1].maxX,top[2].minX)
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.5)).doubleTap()
        expect(preview,"value BEGINSWITH %@","Frame 1;")
        XCTAssertTrue(app.buttons["saveFrames"].exists,"First tap of a double must not enter crop")
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        expect(preview,"value CONTAINS %@","Cropping"); expect(preview,"value CONTAINS %@","edges=0")
        checkHidden(app); XCTAssertEqual(preview.frame,canvas)
        let rect=picture(preview)
        drag(app,from:CGPoint(x:rect.minX+2,y:rect.minY+2),to:CGPoint(x:rect.minX+rect.width*0.2,y:rect.minY+rect.height*0.2))
        let cropped=(preview.value as! String).components(separatedBy:"crop=")[1].components(separatedBy:";")[0]
        XCTAssertNotEqual(cropped,"0.0000,0.0000,1.0000,1.0000")
        checkHidden(app)
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.5)).doubleTap()
        expect(preview,"value BEGINSWITH %@","Frame 2 Cropping")
        XCTAssertTrue((preview.value as! String).contains(cropped)); checkHidden(app)
        capture("crop-portrait-hidden-controls")
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.buttons["resetCrop"].waitForExistence(timeout:5)); XCTAssertEqual(preview.frame,canvas)
        XCTAssertEqual(timeline.value as? String,initialRange.replacingOccurrences(of:"P=0",with:"P=2"))
        app.buttons["resetCrop"].tap(); expect(preview,"value CONTAINS %@","crop=0.0000,0.0000,1.0000,1.0000")
        XCTAssertEqual(timeline.value as? String,initialRange.replacingOccurrences(of:"P=0",with:"P=2"))
        capture("frame-floating-controls-relative-window")
        app.buttons["cancelFrames"].tap(); expect(item(app,"videoSurface"),"value == %@","Paused"); finish(app)
    }
    @MainActor func testLandscapeCropEdgesRotationAndOnePhotoSave() {
        let app=open(), preview=item(app,"framePreview")
        XCUIDevice.shared.orientation = .landscapeLeft
        expect(preview,"value CONTAINS %@","edges=0")
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        expect(preview,"value CONTAINS %@","Cropping")
        expect(preview,"value CONTAINS %@","edges=15")
        let canvas=preview.frame, rect=picture(preview)
        drag(app,from:CGPoint(x:rect.maxX-2,y:rect.minY+2),to:CGPoint(x:rect.maxX-rect.width*0.2,y:rect.minY+rect.height*0.2))
        checkHidden(app); XCTAssertEqual(preview.frame,canvas)
        let crop=(preview.value as! String).components(separatedBy:"crop=")[1].components(separatedBy:";")[0]
        XCTAssertNotEqual(crop,"0.0000,0.0000,1.0000,1.0000")
        capture("crop-landscape-native-edge-priority")
        XCUIDevice.shared.orientation = .portrait
        expect(preview,"value CONTAINS %@","edges=0"); XCTAssertTrue((preview.value as! String).contains(crop)); checkHidden(app)
        XCUIDevice.shared.orientation = .landscapeRight
        expect(preview,"value CONTAINS %@","edges=15"); XCTAssertTrue((preview.value as! String).contains(crop))
        preview.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        expect(preview,"value CONTAINS %@","edges=0")
        XCTAssertTrue(app.buttons["setFrameEnd"].waitForExistence(timeout:5)); app.buttons["setFrameEnd"].tap()
        XCTAssertEqual(item(app,"frameSummary").label,"1 frame")
        capture("crop-landscape-retained-frame")
        app.buttons["saveFrames"].tap()
        XCTAssertTrue(item(app,"frameSaveSuccess").waitForExistence(timeout:30))
        XCTAssertEqual(item(app,"frameSaveSuccess").label,"Saved 1 photo.")
        expect(item(app,"videoSurface"),"value == %@","Paused"); finish(app)
    }
}
