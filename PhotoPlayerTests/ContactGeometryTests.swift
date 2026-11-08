import XCTest
import SwiftUI
@testable import PhotoPlayer

final class ContactGeometryTests: XCTestCase {
    @MainActor
    private func window() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }

    @MainActor
    func testLiveFramesFollowScrollingLayoutReuseAndDetach() {
        let window = window()
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: CGRect(x: 10, y: 100, width: 370, height: 500))
        scroll.contentSize = CGSize(width: 370, height: 1500)
        window.addSubview(scroll)
        let probe = ContactProbeView(frame: CGRect(x: 20, y: 240, width: 150, height: 130))
        probe.number = 3
        scroll.addSubview(probe)
        func measurement(_ point: CGPoint) -> ContactGeometry {
            ContactGeometry(point: point, window: window, probes: [probe], receiver: scroll)
        }
        XCTAssertEqual(measurement(CGPoint(x: 31, y: 341)).uniqueCell?.number, 3)
        scroll.contentOffset.y = 200
        XCTAssertEqual(measurement(CGPoint(x: 31, y: 141)).uniqueCell?.number, 3)
        XCTAssertNil(measurement(CGPoint(x: 31, y: 341)).uniqueCell)
        // Simulate a reused view receiving a different cell identity and bounds.
        probe.number = 12
        probe.frame = CGRect(x: 190, y: 210, width: 140, height: 120)
        let reused = measurement(CGPoint(x: 201, y: 111))
        XCTAssertEqual(reused.uniqueCell?.number, 12)
        XCTAssertEqual(reused.uniqueCell?.frame, CGRect(x: 200, y: 110, width: 140, height: 120))
        XCTAssertEqual(probe.identityRevision, 2)
        probe.removeFromSuperview()
        XCTAssertTrue(measurement(CGPoint(x: 201, y: 111)).cells.isEmpty)
    }

    @MainActor
    func testClippedHiddenAndOverlappingCellsAreNotSilentlySelected() {
        let window = window()
        defer { window.isHidden = true }
        let clip = UIView(frame: CGRect(x: 20, y: 100, width: 100, height: 100))
        clip.clipsToBounds = true
        window.addSubview(clip)
        let first = ContactProbeView(frame: CGRect(x: 0, y: 70, width: 100, height: 80))
        first.number = 3
        clip.addSubview(first)
        func sample(_ point: CGPoint, _ probes: [ContactProbeView]) -> ContactGeometry {
            ContactGeometry(point: point, window: window, probes: probes, receiver: clip)
        }
        XCTAssertEqual(sample(CGPoint(x: 50, y: 180), [first]).uniqueCell?.number, 3)
        let outsideClip = sample(CGPoint(x: 50, y: 220), [first])
        XCTAssertNil(outsideClip.uniqueCell)
        XCTAssertTrue(outsideClip.evidence.contains("rawCandidates=[V3]"))
        XCTAssertTrue(outsideClip.evidence.contains("candidates=[]"))
        let second = ContactProbeView(frame: first.frame)
        second.number = 4
        clip.addSubview(second)
        XCTAssertNil(sample(CGPoint(x: 50, y: 180), [first, second]).uniqueCell)
        XCTAssertEqual(sample(CGPoint(x: 50, y: 180), [first, second]).candidates.count, 2)
        clip.isHidden = true
        XCTAssertTrue(sample(CGPoint(x: 50, y: 180), [first, second]).candidates.isEmpty)
    }

    @MainActor
    func testTransparentProbeCannotInterceptEvenIfInteractionIsReenabled() {
        let window = window()
        defer { window.isHidden = true }
        let button = UIButton(frame: CGRect(x: 20, y: 100, width: 160, height: 130))
        window.addSubview(button)
        let probe = ContactProbeView(frame: button.bounds)
        button.addSubview(probe)
        let point = CGPoint(x: 80, y: 160)
        XCTAssertTrue(window.hitTest(point, with: nil) === button)
        probe.isUserInteractionEnabled = true
        XCTAssertFalse(probe.point(inside: CGPoint(x: 10, y: 10), with: nil))
        XCTAssertNil(probe.hitTest(CGPoint(x: 10, y: 10), with: nil))
        XCTAssertTrue(window.hitTest(point, with: nil) === button)
    }

    @MainActor
    func testOutsideInputRetainsReceiverAndNearbyCellsWithoutUserText() {
        let window = window()
        defer { window.isHidden = true }
        let probe = ContactProbeView(frame: CGRect(x: 20, y: 100, width: 160, height: 130))
        probe.number = 5
        window.addSubview(probe)
        let receiver = UILabel(frame: CGRect(x: 200, y: 100, width: 160, height: 130))
        receiver.text = "PRIVATE_FILENAME.mov"
        receiver.accessibilityLabel = "PRIVATE_ASSET_ID"
        window.addSubview(receiver)
        let snapshot = ContactGeometry(point: CGPoint(x: 205, y: 110), window: window, probes: [probe], receiver: receiver)
        XCTAssertNil(snapshot.uniqueCell)
        XCTAssertTrue(snapshot.evidence.contains("point=(205.0,110.0)"))
        XCTAssertTrue(snapshot.evidence.contains("UILabel{frame=(200.0,100.0,160.0,130.0)"))
        XCTAssertTrue(snapshot.evidence.contains("V5{"))
        XCTAssertFalse(snapshot.evidence.contains("PRIVATE"))
    }

    @MainActor
    func testControlRegionIsDistinctFromCellAndForeignWindow() {
        let window = window()
        defer { window.isHidden = true }
        let cell = ContactProbeView(frame: CGRect(x: 20, y: 100, width: 160, height: 130))
        cell.number = 6
        window.addSubview(cell)
        let control = ContactProbeView(frame: cell.frame)
        control.control = "copy.library"
        window.addSubview(control)
        let point = CGPoint(x: 80, y: 160)
        let snapshot = ContactGeometry(point: point, window: window, probes: [cell, control], receiver: window)
        XCTAssertNil(snapshot.uniqueCell)
        XCTAssertEqual(snapshot.controls, ["copy.library"])
        XCTAssertEqual(snapshot.candidates.map(\.number), [6])
        let other = UIWindow(frame: window.frame)
        other.addSubview(cell)
        XCTAssertTrue(ContactGeometry(point: point, window: window, probes: [cell], receiver: window).cells.isEmpty)
    }
}
