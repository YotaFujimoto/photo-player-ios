import XCTest
import UIKit
import UIKit.UIGestureRecognizerSubclass
@testable import PhotoPlayer

// The concrete UIKit recognizer owns its transitions and may reset a manually
// assigned state without a touch sequence. This fixture supplies action inputs;
// the UI suite separately verifies actual recognition from physical gestures.
private final class HoldStateFixture: UILongPressGestureRecognizer {
    private var suppliedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { suppliedState }
        set { suppliedState = newValue }
    }
}

final class VideoGestureTests: XCTestCase {
    @MainActor
    func testHoldEndsOnReleaseCancellationFailureAndWindowRemoval() {
        let view = VideoGestureView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let window = UIWindow(frame: view.frame)
        let windowRecognizers = Set((window.gestureRecognizers ?? []).map(ObjectIdentifier.init))
        window.addSubview(view)
        view.layoutIfNeeded()
        var held = false
        var skips = 0
        view.onHoldBegan = { held = true }
        view.onHoldEnded = { held = false }
        view.onSkip = { _ in skips += 1 }
        for end in [UIGestureRecognizer.State.ended, .cancelled] {
            let recognizer = HoldStateFixture()
            recognizer.state = .began
            XCTAssertEqual(recognizer.state, .began)
            view.held(recognizer)
            XCTAssertTrue(held)
            recognizer.state = end
            view.held(recognizer)
            XCTAssertFalse(held)
        }
        let failed = HoldStateFixture()
        failed.state = .failed
        held = true
        view.held(failed)
        XCTAssertFalse(held)
        held = true
        view.removeFromSuperview()
        XCTAssertFalse(held)
        XCTAssertEqual(skips, 0)
        XCTAssertEqual(Set((window.gestureRecognizers ?? []).map(ObjectIdentifier.init)), windowRecognizers)
    }

    @MainActor
    func testResizeAndDismantleCancelHoldWithoutInstallingRecognizersOnControls() {
        let view = VideoGestureView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        var ended = 0
        view.onHoldEnded = { ended += 1 }
        view.frame.size = CGSize(width: 600, height: 320)
        view.layoutIfNeeded()
        XCTAssertGreaterThan(ended, 0)
        let before = ended
        PlayerSurface.dismantleUIView(view, coordinator: ())
        XCTAssertGreaterThan(ended, before)
        XCTAssertNil(view.onHoldBegan)
        XCTAssertNil(view.onHoldEnded)
        XCTAssertEqual(view.doubleTap.numberOfTapsRequired, 2)
        XCTAssertEqual(Set(view.gestureRecognizers!.map(ObjectIdentifier.init)),
                       Set([view.doubleTap, view.hold].map(ObjectIdentifier.init)))
    }
}
