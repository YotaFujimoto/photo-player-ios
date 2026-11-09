import XCTest
import SwiftUI
@testable import PhotoPlayer

final class SeekInteractionTests: XCTestCase {
    func testBarMapsFullWidthAndClampsInvalidOrOutsidePositions() {
        for width in [248.0, 390, 720] {
            XCTAssertEqual(SeekInteractionPolicy.barPosition(x: 0, width: width, duration: 120), 0)
            XCTAssertEqual(SeekInteractionPolicy.barPosition(x: width, width: width, duration: 120), 120)
            XCTAssertEqual(SeekInteractionPolicy.barPosition(x: width / 4, width: width, duration: 120), 30)
            XCTAssertEqual(SeekInteractionPolicy.barPosition(x: -50, width: width, duration: 120), 0)
            XCTAssertEqual(SeekInteractionPolicy.barPosition(x: width + 50, width: width, duration: 120), 120)
        }
        XCTAssertEqual(SeekInteractionPolicy.barPosition(x: .nan, width: 300, duration: 120), 0)
        XCTAssertEqual(SeekInteractionPolicy.barPosition(x: 50, width: 0, duration: 120), 0)
    }

    func testHorizontalSensitivityIsRelativeAndIndependentOfOrientation() {
        for width in [320.0, 760] {
            XCTAssertEqual(SeekInteractionPolicy.horizontalPosition(origin: 100, translation: width, width: width, duration: 300), 160)
            XCTAssertEqual(SeekInteractionPolicy.horizontalPosition(origin: 100, translation: -width / 2, width: width, duration: 300), 70)
            XCTAssertEqual(SeekInteractionPolicy.horizontalPosition(origin: 5, translation: -width, width: width, duration: 300), 0)
            XCTAssertEqual(SeekInteractionPolicy.horizontalPosition(origin: 290, translation: width, width: width, duration: 300), 300)
        }
        XCTAssertEqual(SeekInteractionPolicy.horizontalPosition(origin: 100, translation: .nan, width: 320, duration: 300), 100)
    }

    func testDirectionRequiresDeliberateHorizontalMovement() {
        for (x, y) in [(0.0, 0.0), (11, 0), (5, 8), (13, 10)] {
            XCTAssertEqual(SeekInteractionPolicy.direction(x: x, y: y), .pending)
        }
        for (x, y) in [(12.0, 0.0), (-12, 0), (15, 10), (-30, -20)] {
            XCTAssertEqual(SeekInteractionPolicy.direction(x: x, y: y), .horizontal)
        }
        for (x, y) in [(0.0, 12.0), (12, 20), (30, -31)] {
            XCTAssertEqual(SeekInteractionPolicy.direction(x: x, y: y), .rejected)
        }
    }

    func testFeedbackReportsRealDistanceAndBoundaries() {
        XCTAssertEqual(SkipFeedback(forward: true, origin: 10, target: 20, duration: 30).text, "+10s")
        XCTAssertEqual(SkipFeedback(forward: false, origin: 20, target: 10, duration: 30).text, "−10s")
        XCTAssertEqual(SkipFeedback(forward: false, origin: 2.5, target: 0, duration: 30).text, "−2.5s · Start")
        XCTAssertEqual(SkipFeedback(forward: true, origin: 29, target: 30, duration: 30).text, "+1s · End")
        XCTAssertEqual(SkipFeedback(forward: false, origin: 0, target: 0, duration: 30).text, "Start")
        XCTAssertEqual(SkipFeedback(forward: true, origin: 30, target: 30, duration: 30).text, "End")
    }

    @MainActor
    func testTransportLayoutDoesNotReserveStatusSpaceOrMoveOnBuffering() throws {
        for width in [248.0, 390] {
            let states = ["Loading…", "Playing", "Buffering…", "Seeking…", "Paused", "Error"]
            var baseline: CGSize?
            for status in states {
                let controls = PlaybackTransportControls(state: PlaybackTransportState(
                    position: 10, duration: 30, isReady: status != "Loading…", canPlaySlow: status != "Loading…",
                    showsPause: status == "Playing", stateText: status))
                let host = UIHostingController(rootView: controls)
                let size = host.sizeThatFits(in: CGSize(width: width, height: 1000))
                XCTAssertGreaterThan(size.height, 80)
                if let baseline { XCTAssertEqual(size.height, baseline.height, accuracy: 0.5, status) }
                else { baseline = size }
            }
            let diagnostics = UIHostingController(rootView: PlaybackTransportControls(state: PlaybackTransportState(), diagnostics: true))
            let diagnosticHeight = diagnostics.sizeThatFits(in: CGSize(width: width, height: 1000)).height
            XCTAssertGreaterThan(diagnosticHeight, try XCTUnwrap(baseline).height + 12,
                                 "The normal layout must remove the status row and its spacing entirely")
        }
    }
}
