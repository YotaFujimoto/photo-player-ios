import XCTest
import UIKit

final class SingleTapTests: XCTestCase {
    @MainActor func testShortSingleTapsAfterReturningWithDiagnosticsOn() { checkReturning(diagnostics: true) }
    @MainActor func testShortSingleTapsAfterReturningWithDiagnosticsOff() { checkReturning(diagnostics: false) }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication.photoPlayerForTesting()
        app.launchArguments = ["--selection-diagnostics"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    func testCopyDistinguishesNewUnacceptedContactFromPreviousPlayback() {
        let app = launch(["--verify-diagnostic-copy"])
        let frame = app.buttons["videoCard.3"].frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 55))
        start.press(forDuration: 0.03)
        verifyOpened(app, number: 3, dimensions: "202x202", diagnostics: true)
        app.buttons["closePlayer"].tap()
        // A deliberate scroll is a real contact with no selection action.
        // It must get its own record after the previous player's close history.
        start.press(forDuration: 0.03, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let journal = app.staticTexts["selectionJournal.library"]
        let latest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "C2 動画3 選択処理の記録なし"), object: journal)
        XCTAssertEqual(XCTWaiter.wait(for: [latest], timeout: 10), .completed)
        verifyCounts(app, accepted: 1, shown: 1, requested: 1, received: 1, ready: 1, inPlayer: false)
        let report = journal.value as! String
        XCTAssertTrue(report.contains("cover.dismiss"))
        XCTAssertTrue(report.contains("C2 V3 end=true"))
        XCTAssertTrue(report.contains("selectionCandidate=-"))
        let copy = app.buttons["copySelectionTrace.library"]
        copy.tap()
        let copied = copy.value as! String
        XCTAssertTrue(copied.hasPrefix(report), "Copy retains the report; its own window input may append events")
        XCTAssertTrue(copied.contains("input.other.begin"))
        XCTAssertTrue(copied.contains("control.action name=copy.library"))
        XCTAssertTrue(copied.contains("controls=[copy.library]"))
        attach("journal-new-contact-after-close-copied")
    }

    @MainActor
    func testCopyKeepsDistinctOperationsWhenReopeningSameVideo() {
        let app = launch(["--verify-diagnostic-copy"])
        let frame = app.buttons["videoCard.3"].frame
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 55))
        for _ in 0..<3 {
            target.press(forDuration: 0.03)
            verifyOpened(app, number: 3, dimensions: "202x202", diagnostics: true)
            app.buttons["closePlayer"].tap()
        }
        verifyCounts(app, accepted: 3, shown: 3, requested: 3, received: 3, ready: 3, inPlayer: false)
        let copy = app.buttons["copySelectionTrace.library"]
        copy.tap()
        let report = copy.value as! String
        for number in 1...3 {
            XCTAssertTrue(report.contains("S\(number) V3 contactCandidate=C\(number) result=終了"), report)
            XCTAssertTrue(report.contains("S\(number) V3 view.appear"), report)
            XCTAssertTrue(report.contains("S\(number) V3 close.request"), report)
        }
        XCTAssertTrue(report.contains("reason=fullScreenCover.binding"))
        XCTAssertTrue(report.contains("control.action name=copy.library"))
        attach("journal-same-video-three-operations-copied")
    }

    @MainActor
    private func checkReturning(diagnostics: Bool) {
        let app = launch()
        if !diagnostics { app.buttons["selectionDiagnostics"].tap() }
        // Cache positions BEFORE opening. After Close there is no sleep, query,
        // second tap, or retry before the next single physical contact.
        let targets = [3, 4, 2, 3].map { number in
            let card = app.buttons["videoCard.\(number)"]
            let frame = card.frame
            return (number, frame.midX, frame.minY + 55, card.value as! String)
        }
        for (number, x, y, dimensions) in targets {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
                .press(forDuration: 0.03)
            verifyOpened(app, number: number, dimensions: dimensions, diagnostics: diagnostics)
            app.buttons["closePlayer"].tap()
        }
        if !diagnostics { app.buttons["selectionDiagnostics"].tap() }
        verifyCounts(app, accepted: 4, shown: 4, requested: 4, received: 4, ready: 4, inPlayer: false)
        XCTAssertTrue(trace(app).contains("contacts=4;"), "Each opening requires exactly ONE contact: \(trace(app))")
        attach("single-tap-return-\(diagnostics ? "on" : "off")")
    }

    @MainActor
    func testSingleContactsWithSmallFingerMovement() {
        let app = launch()
        for number in [3, 4, 1, 2] {
            let card = app.buttons["videoCard.\(number)"]
            let frame = card.frame
            let dimensions = card.value as! String
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 55))
            let end = start.withOffset(CGVector(dx: number.isMultiple(of: 2) ? 3 : -3, dy: 3))
            // A single finger contact with 4.2pt of movement, not a second tap.
            start.press(forDuration: 0.03, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            verifyOpened(app, number: number, dimensions: dimensions, diagnostics: true)
            app.buttons["closePlayer"].tap()
        }
        verifyCounts(app, accepted: 4, shown: 4, requested: 4, received: 4, ready: 4, inPlayer: false)
        XCTAssertTrue(trace(app).contains("contacts=4;"), trace(app))
        attach("single-tap-small-movement")
    }

    @MainActor
    func testSingleTapAfterScrollAndDuringThumbnailLoad() {
        let app = launch(["--delay-thumbnails"])
        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.03, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        let last = app.buttons["videoCard.12"]
        XCTAssertTrue(last.isHittable)
        let frame = last.frame
        let dimensions = last.value as! String
        let before = trace(app)
        XCTAssertTrue(before.contains("accepted=0;"), "Scrolling must not select a video: \(before)")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 55)).press(forDuration: 0.03)
        verifyOpened(app, number: 12, dimensions: dimensions, diagnostics: true)
        verifyCounts(app, accepted: 1, shown: 1, requested: 1, received: 1, ready: 1)
        XCTAssertNotEqual(trace(app), before)
        app.buttons["closePlayer"].tap()

        app.buttons["refreshLibrary"].tap()
        XCTAssertTrue(last.images["thumbnailPlaceholder"].waitForExistence(timeout: 3))
        // One physical tap while the real PhotoKit thumbnail callback is held.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 55)).press(forDuration: 0.03)
        verifyOpened(app, number: 12, dimensions: dimensions, diagnostics: true)
        verifyCounts(app, accepted: 2, shown: 2, requested: 2, received: 2, ready: 2)
        attach("single-tap-scrolled-loading")
    }

    @MainActor
    func testOneTapPresentsVisibleLoadingBeforePhotoKitCompletes() {
        let app = launch(["--hold-player-result"])
        let card = app.buttons["videoCard.3"]
        let frame = card.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 55)).press(forDuration: 0.03)
        let header = app.staticTexts["selectedVideo"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.label, "Video 3")
        XCTAssertTrue(app.staticTexts["videoLoading"].waitForExistence(timeout: 10))
        verifyCounts(app, accepted: 1, shown: 1, requested: 1, received: 0, ready: 0)
        attach("single-tap-visible-loading")
        let release = app.buttons["releasePlayerResult"]
        let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: release)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed)
        release.tap()
        verifyOpened(app, number: 3, dimensions: "202x202", diagnostics: true)
        verifyCounts(app, accepted: 1, shown: 1, requested: 1, received: 1, ready: 1)
        XCTAssertTrue(trace(app).contains("contacts=1;"))
        attach("single-tap-result-received")
    }

    @MainActor
    private func verifyOpened(_ app: XCUIApplication, number: Int, dimensions: String, diagnostics: Bool) {
        let selected = app.staticTexts["selectedVideo"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "ONE tap must present the player. \(trace(app))")
        XCTAssertEqual(selected.label, diagnostics ? "Video \(number)" : "Playback")
        XCTAssertEqual(selected.value as? String, dimensions)
        if diagnostics {
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", dimensions),
                                                   object: app.staticTexts["loadedVideoSize"])
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
        } else {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: app.buttons["playPause"])
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        }
    }

    @MainActor
    private func trace(_ app: XCUIApplication) -> String {
        let player = app.staticTexts["selectionTrace.player"]
        let trace = player.exists ? player : app.staticTexts["selectionTrace.library"]
        return trace.exists ? (trace.value as? String ?? trace.label) : "diagnostics hidden"
    }

    @MainActor
    private func verifyCounts(_ app: XCUIApplication, accepted: Int, shown: Int, requested: Int, received: Int, ready: Int, inPlayer: Bool = true) {
        let expected = "accepted=\(accepted);shown=\(shown);requested=\(requested);received=\(received);ready=\(ready)"
        let predicate = NSPredicate(format: "value CONTAINS %@", expected)
        let counts = XCTNSPredicateExpectation(predicate: predicate,
            object: app.staticTexts[inPlayer ? "selectionTrace.player" : "selectionTrace.library"])
        XCTAssertEqual(XCTWaiter.wait(for: [counts], timeout: 10), .completed, trace(app))
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
