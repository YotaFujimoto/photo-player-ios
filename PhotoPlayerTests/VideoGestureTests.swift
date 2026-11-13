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

private final class HorizontalStateFixture: HorizontalSeekGestureRecognizer {
    private var suppliedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { suppliedState }
        set { suppliedState = newValue }
    }
}

private final class TapStateFixture: UITapGestureRecognizer {
    private var suppliedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { suppliedState }
        set { suppliedState = newValue }
    }
}

final class VideoGestureTests: XCTestCase {
    @MainActor func testSingleTapIsFullscreenOnlyAndTeardownClearsCallbacks() {
        let view = VideoGestureView(frame: CGRect(x: 0, y: 0, width: 600, height: 320))
        var taps = 0, interactions: [Bool] = []
        view.onSingleTap = { taps += 1 }
        view.onInteractionChanged = { interactions.append($0) }
        let tap = TapStateFixture(); tap.state = .ended
        view.singleTapped(tap); XCTAssertEqual(taps, 0)
        view.singleTap.isEnabled = true
        tap.state = .failed; view.singleTapped(tap); XCTAssertEqual(taps, 0)
        tap.state = .ended; view.singleTapped(tap); XCTAssertEqual(taps, 1)
        let held = HoldStateFixture(); held.state = .began; view.held(held)
        XCTAssertEqual(interactions, [true])
        view.cancelGestures(); XCTAssertEqual(interactions, [true, false])
        XCTAssertEqual(view.playerLayer.videoGravity, .resizeAspect)
        PlayerSurface.dismantleUIView(view, coordinator: ())
        XCTAssertNil(view.onSingleTap); XCTAssertNil(view.onInteractionChanged)
    }
    @MainActor
    func testHorizontalRecognitionAndCancellationDiscardLateEndOnResizeAndRemoval() {
        let view = VideoGestureView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let window = UIWindow(frame: view.frame)
        window.addSubview(view); view.layoutIfNeeded()
        var begins = 0, commits = 0, cancels = 0
        view.onSwipeBegan = { begins += 1; return true }
        view.onSwipeEnded = { commits += 1 }
        view.onSwipeCancelled = { cancels += 1 }
        for resize in [true, false] {
            let gesture = HorizontalStateFixture()
            gesture.start(at: .zero)
            gesture.move(to: CGPoint(x: 5, y: 2))
            XCTAssertEqual(gesture.state, .possible)
            gesture.move(to: CGPoint(x: 15, y: 2))
            XCTAssertEqual(gesture.state, .began)
            view.swiped(gesture)
            if resize { view.frame.size.width = 600; view.layoutIfNeeded() }
            else { view.removeFromSuperview() }
            gesture.state = .ended; view.swiped(gesture)
        }
        XCTAssertEqual(begins, 2); XCTAssertEqual(cancels, 2); XCTAssertEqual(commits, 0)
        let vertical = HorizontalStateFixture()
        vertical.start(at: .zero); vertical.move(to: CGPoint(x: 2, y: 20))
        XCTAssertEqual(vertical.state, .failed)
        vertical.move(to: CGPoint(x: 50, y: 20))
        XCTAssertEqual(vertical.state, .failed, "A rejected vertical contact cannot later become horizontal")
    }

    @MainActor
    func testHorizontalCommitAndRejectionAreNotDuplicated() {
        let view = VideoGestureView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.layoutIfNeeded()
        var accepted = true, commits = 0
        view.onSwipeBegan = { accepted }
        view.onSwipeEnded = { commits += 1 }
        let gesture = HorizontalStateFixture()
        gesture.state = .began; view.swiped(gesture)
        gesture.state = .ended; view.swiped(gesture); view.swiped(gesture)
        XCTAssertEqual(commits, 1)
        accepted = false
        gesture.state = .began; view.swiped(gesture)
        gesture.state = .ended; view.swiped(gesture)
        XCTAssertEqual(commits, 1)
    }

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
                       Set([view.singleTap, view.doubleTap, view.hold, view.horizontal].map(ObjectIdentifier.init)))
    }
}
