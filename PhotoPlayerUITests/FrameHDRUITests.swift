import XCTest
import UIKit

final class FrameHDRUITests: XCTestCase {
    @MainActor private func expect(_ element: XCUIElement, _ predicate: NSPredicate) {
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:element)],timeout:15),.completed)
    }
    @MainActor func testPhotoKitHDRVariableCaptureOpensSavesAndCopiesReasons() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication.photoPlayerForTesting()
        app.launchArguments=["--verify-diagnostic-copy"]
        app.launch()
        let card=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'videoCard.' AND value == '320x192'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:20)); card.tap()
        let surface=app.otherElements.matching(identifier:"videoSurface").firstMatch
        expect(surface,NSPredicate(format:"value == 'Playing'"))
        app.playerButton("playPause").tap(); expect(surface,NSPredicate(format:"value == 'Paused'"))
        app.playerButton("rateMenu").tap(); app.buttons.matching(identifier:"0.25×").firstMatch.tap()
        app.otherElements.matching(identifier:"seekSlider").firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0.5)).tap()
        expect(app.staticTexts.matching(identifier:"playbackPosition").firstMatch,NSPredicate(format:"label == '0:00'"))
        app.playerButton("extractFrames").tap()
        let done=app.buttons.matching(identifier:"saveFrames").firstMatch
        expect(done,NSPredicate(format:"enabled == true"))
        let summary=app.staticTexts.matching(identifier:"frameSummary").firstMatch
        XCTAssertTrue(summary.label.hasPrefix("≈"),summary.label)
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name="HDR-HEVC-variable-frame-preview"; attachment.lifetime = .keepAlways; add(attachment)
        // P starts at W0; equal endpoints save one real frame.
        app.buttons.matching(identifier:"setFrameEnd").firstMatch.tap()
        XCTAssertEqual(summary.label,"1 frame")
        done.tap()
        let success=app.staticTexts.matching(identifier:"frameSaveSuccess").firstMatch
        XCTAssertTrue(success.waitForExistence(timeout:30)); XCTAssertEqual(success.label,"Saved 1 photo.")
        expect(surface,NSPredicate(format:"value == 'Paused'"))
        XCTAssertEqual(app.playerButton("rateMenu").value as? String,"0.25×")
        app.playerButton("playerDiagnostics").tap()
        let copy=app.buttons.matching(identifier:"copySelectionTrace.player").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout:10)); copy.tap()
        let report=copy.value as? String ?? ""
        for value in ["[frame extraction:","transfer=HLG","cadence=variable","forceSDR","SDR-sRGB8","operationStage=saved"] {
            XCTAssertTrue(report.contains(value),"Missing \(value) in anonymous diagnostics")
        }
        XCTAssertFalse(report.contains("frames-hdr-ui")); XCTAssertFalse(report.contains("file:"))
        app.playerButton("closePlayer").tap()
        XCTAssertTrue(card.waitForExistence(timeout:10)); app.terminate()
        XCTAssertEqual(app.state,.notRunning)
    }
}
