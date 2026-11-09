import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Wait for a deliberate horizontal movement. Unlike a generic pan, vertical
/// movement fails before recognition and a stationary contact can become a hold.
class HorizontalSeekGestureRecognizer: UIGestureRecognizer {
    private var trackedTouch: UITouch?
    private var origin = CGPoint.zero
    private(set) var translation = CGPoint.zero

    func start(at point: CGPoint) { origin = point; translation = .zero }
    func move(to point: CGPoint) {
        guard state == .possible || state == .began || state == .changed else { return }
        translation = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        if state == .possible {
            switch SeekInteractionPolicy.direction(x: Double(translation.x), y: Double(translation.y)) {
            case .horizontal: state = .began
            case .rejected: state = .failed
            case .pending: break
            }
        } else { state = .changed }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled
            return
        }
        trackedTouch = touch
        start(at: touch.location(in: view))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        move(to: touch.location(in: view))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        if state == .began || state == .changed {
            translation = CGPoint(x: touch.location(in: view).x - origin.x, y: touch.location(in: view).y - origin.y)
            state = .ended
        } else if state == .possible { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .cancelled }
        else if state == .possible { state = .failed }
    }
    override func reset() {
        super.reset()
        trackedTouch = nil; origin = .zero; translation = .zero
    }
}
