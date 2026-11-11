import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Any-direction drag, enabled only in crop mode. A failed tap stays available
/// to the exclusive single/double recognizers. No press timer or synthetic tap.
final class CropGestureRecognizer: UIGestureRecognizer {
    private var touch: UITouch?
    private(set) var origin = CGPoint.zero
    private(set) var translation = CGPoint.zero
    func start(at point: CGPoint) { origin = point; translation = .zero }
    func move(to point: CGPoint) {
        guard state == .possible || state == .began || state == .changed else { return }
        translation = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        if state == .possible {
            if hypot(translation.x, translation.y) >= 6 { state = .began }
        } else { state = .changed }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touch == nil, touches.count == 1, let first = touches.first else { state = .failed; return }
        touch = first; start(at: first.location(in: view))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch, touches.contains(touch) { move(to: touch.location(in: view)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch, touches.contains(touch) else { return }
        if state == .began || state == .changed {
            translation = CGPoint(x: touch.location(in: view).x - origin.x, y: touch.location(in: view).y - origin.y)
            state = .ended
        } else if state == .possible { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() { super.reset(); touch = nil; origin = .zero; translation = .zero }
}
