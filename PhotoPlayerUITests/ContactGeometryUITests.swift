import XCTest

final class ContactGeometryUITests: XCTestCase {
    @MainActor
    func testLiveCellGeometryAfterScrollReturnReloadAndToggle() {
        continueAfterFailure = false
        let app = XCUIApplication.photoPlayerForTesting()
        app.launchArguments = ["--selection-diagnostics", "--verify-diagnostic-copy", "--delay-thumbnails"]
        app.launch()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 20))
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp(velocity: .fast)
        let last = reveal(12, in: app)
        var expected: [(Int, CGRect, CGPoint)] = []
        expected.append(openOnce(12, card: last, in: app, bottom: false, diagnostics: true))
        app.buttons["closePlayer"].tap()
        app.buttons["selectionDiagnostics"].tap()
        scroll.swipeDown(velocity: .fast)
        expected.append(openOnce(3, card: reveal(3, in: app), in: app, bottom: true, diagnostics: false))
        app.buttons["closePlayer"].tap()
        app.buttons["selectionDiagnostics"].tap()
        let fourth = reveal(4, in: app)
        app.buttons["refreshLibrary"].tap()
        XCTAssertTrue(fourth.images["thumbnailPlaceholder"].waitForExistence(timeout: 3))
        expected.append(openOnce(4, card: fourth, in: app, bottom: false, diagnostics: true))
        app.buttons["closePlayer"].tap()
        let report = copy(app)
        for (number, frame, point) in expected {
            let line = report.components(separatedBy: "\n").first {
                $0.contains(" V\(number) contact.begin ")
            }
            XCTAssertNotNil(line, report)
            guard let line else { return }
            XCTAssertTrue(line.contains("candidates=[V\(number)]"), line)
            XCTAssertFalse(line.contains("ContactProbeView{"), "The passive probe must never receive the physical touch")
            let loggedPoint = numbers(after: "point=", in: line, count: 2)
            XCTAssertEqual(loggedPoint[0], Double(point.x), accuracy: 2)
            XCTAssertEqual(loggedPoint[1], Double(point.y), accuracy: 2)
            let candidate = line.components(separatedBy: "V\(number){").last!
            let loggedFrame = numbers(after: "frame=", in: candidate, count: 4)
            for (actual, expected) in zip(loggedFrame, [frame.minX, frame.minY, frame.width, frame.height]) {
                XCTAssertEqual(actual, Double(expected), accuracy: 2, "Probe bounds must match the displayed cell's independently queried bounds")
            }
            XCTAssertTrue(line.contains("diagnostics=\(number != 3)"), line)
        }
        XCTAssertTrue(report.contains("control.action name=library.refresh"))
        XCTAssertTrue(report.contains("control.action name=diagnostics.toggle"))
        XCTAssertTrue(report.contains("controls=[library.refresh]"), report)
        XCTAssertEqual(report.components(separatedBy: "\n").filter { $0.contains(" contact.begin ") }.count, 3,
                       "Toolbar controls over scrolled cells must not create extra cell contacts")
        XCTAssertTrue(report.contains("controls=[copy.library]"))
        attach("geometry-scroll-return-toggle-copied")
    }

    @MainActor
    func testCopyAndToggleHaveDistinctControlInputsAndNeverSelect() {
        continueAfterFailure = false
        let app = XCUIApplication.photoPlayerForTesting()
        app.launchArguments = ["--verify-diagnostic-copy"]
        app.launch()
        XCTAssertTrue(app.buttons["videoCard.1"].waitForExistence(timeout: 20))
        app.buttons["selectionDiagnostics"].tap()
        let report = copy(app)
        XCTAssertTrue(report.contains("controls=[diagnostics.toggle]"), report)
        XCTAssertTrue(report.contains("controls=[copy.library]"), report)
        XCTAssertTrue(report.contains("control.action name=diagnostics.toggle inputCandidate=I1"), report)
        XCTAssertTrue(report.contains("control.action name=copy.library inputCandidate=I2"), report)
        XCTAssertFalse(report.contains("action.enter source=Button.action"), report)
        let counts = app.staticTexts["selectionTrace.library"].value as! String
        XCTAssertEqual(counts, "contacts=0;accepted=0;shown=0;requested=0;received=0;ready=0")
        XCTAssertFalse(app.staticTexts["selectedVideo"].exists)
        attach("geometry-control-inputs-copied")
    }

    @MainActor
    private func openOnce(_ number: Int, card: XCUIElement, in app: XCUIApplication,
                          bottom: Bool, diagnostics: Bool) -> (Int, CGRect, CGPoint) {
        let frame = card.frame
        let dimensions = card.value as! String
        let point = CGPoint(x: frame.midX, y: bottom ? frame.maxY - 3 : frame.minY + 3)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).press(forDuration: 0.03)
        let selected = app.staticTexts["selectedVideo"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "One physical contact must open the video")
        XCTAssertEqual(selected.label, diagnostics ? "Video \(number)" : "Playback")
        XCTAssertEqual(selected.value as? String, dimensions)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: app.buttons["playPause"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        return (number, frame, point)
    }

    @MainActor
    private func reveal(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        let card = app.buttons["videoCard.\(number)"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let viewport = scroll.frame.insetBy(dx: 0, dy: 5)
            if card.exists, card.frame.height > 0 {
                if viewport.contains(card.frame), card.isHittable { return card }
                if card.frame.minY < viewport.minY { scroll.swipeDown(); continue }
            }
            scroll.swipeUp()
        }
        XCTFail("Cell \(number) is not fully visible")
        return card
    }

    @MainActor
    private func copy(_ app: XCUIApplication) -> String {
        let button = app.buttons["copySelectionTrace.library"]
        button.tap()
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "control.action name=copy.library"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 10), .completed)
        return button.value as! String
    }

    private func numbers(after marker: String, in text: String, count: Int) -> [Double] {
        guard let range = text.range(of: marker + "("), let end = text[range.upperBound...].firstIndex(of: ")") else {
            XCTFail("Missing numeric geometry: \(text)")
            return Array(repeating: .nan, count: count)
        }
        let values = text[range.upperBound..<end].split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, count)
        return values.count == count ? values : Array(repeating: .nan, count: count)
    }

    @MainActor
    private func attach(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
