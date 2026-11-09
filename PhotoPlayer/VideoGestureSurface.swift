import SwiftUI
import AVFoundation

/// Recognizers belong only to the video view, never the window or controls.
final class VideoGestureView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onSkip: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?
    var onSwipeBegan: (() -> Bool)?
    var onSwipeChanged: ((Double, Double) -> Void)?
    var onSwipeEnded: (() -> Void)?
    var onSwipeCancelled: (() -> Void)?
    private(set) var doubleTap = UITapGestureRecognizer()
    private(set) var singleTap = UITapGestureRecognizer()
    private(set) var hold = UILongPressGestureRecognizer()
    private(set) var horizontal = HorizontalSeekGestureRecognizer()
    private var swipeAccepted = false
    private var holdActive = false
    private var lastSize = CGSize.zero
    var cancellationID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(tapped(_:)))
        singleTap.addTarget(self, action: #selector(singleTapped(_:)))
        singleTap.isEnabled = false
        hold.addTarget(self, action: #selector(held(_:)))
        horizontal.addTarget(self, action: #selector(swiped(_:)))
        // Short taps make the standard long-press recognizer fail naturally.
        // A held press and a double tap cannot both act on the same contact.
        doubleTap.require(toFail: hold)
        doubleTap.require(toFail: horizontal)
        singleTap.require(toFail: doubleTap)
        singleTap.require(toFail: hold)
        singleTap.require(toFail: horizontal)
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(hold)
        addGestureRecognizer(horizontal)
        isAccessibilityElement = true
        accessibilityLabel = "Video"
        accessibilityIdentifier = "videoSurface"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Skip back 10 seconds", target: self, selector: #selector(skipBack)),
            UIAccessibilityCustomAction(name: "Skip forward 10 seconds", target: self, selector: #selector(skipForward)),
            UIAccessibilityCustomAction(name: "Show or hide controls", target: self, selector: #selector(toggleControls))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func singleTapped(_ recognizer: UITapGestureRecognizer) {
        guard singleTap.isEnabled, recognizer.state == .ended else { return }
        onSingleTap?()
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onSkip?(recognizer.location(in: self).x >= bounds.midX)
    }

    @objc func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            holdActive = true
            onInteractionChanged?(true)
            onHoldBegan?()
        case .changed:
            if !bounds.contains(recognizer.location(in: self)) { cancelHold() }
        case .ended, .cancelled, .failed: finishHold()
        default: break
        }
    }

    func cancelHold() {
        finishHold()
        hold.isEnabled = false
        hold.isEnabled = true
    }

    private func finishHold() {
        onHoldEnded?()
        if holdActive { holdActive = false; onInteractionChanged?(false) }
    }

    @objc func swiped(_ recognizer: HorizontalSeekGestureRecognizer) {
        switch recognizer.state {
        case .began:
            swipeAccepted = onSwipeBegan?() == true
            if !swipeAccepted { horizontal.isEnabled = false; horizontal.isEnabled = true; return }
            onInteractionChanged?(true)
            onSwipeChanged?(Double(recognizer.translation.x), Double(bounds.width))
        case .changed:
            if swipeAccepted { onSwipeChanged?(Double(recognizer.translation.x), Double(bounds.width)) }
        case .ended:
            guard swipeAccepted else { return }
            swipeAccepted = false
            onSwipeChanged?(Double(recognizer.translation.x), Double(bounds.width))
            onSwipeEnded?()
            onInteractionChanged?(false)
        case .failed, .cancelled:
            if swipeAccepted { swipeAccepted = false; onSwipeCancelled?(); onInteractionChanged?(false) }
        default: break
        }
    }

    func cancelGestures() {
        if swipeAccepted { swipeAccepted = false; onSwipeCancelled?(); onInteractionChanged?(false) }
        cancelHold()
        horizontal.isEnabled = false; horizontal.isEnabled = true
        doubleTap.isEnabled = false; doubleTap.isEnabled = true
        let singleEnabled = singleTap.isEnabled
        singleTap.isEnabled = false; singleTap.isEnabled = singleEnabled
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelGestures() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != bounds.size { cancelGestures(); lastSize = bounds.size }
    }

    @objc private func skipBack() -> Bool { onSkip?(false); return true }
    @objc private func skipForward() -> Bool { onSkip?(true); return true }
    @objc private func toggleControls() -> Bool {
        guard singleTap.isEnabled else { return false }
        onSingleTap?(); return true
    }
}

struct PlayerSurface: UIViewRepresentable {
    let model: PlaybackModel
    var fullscreen = false
    var onSingleTap: () -> Void = {}
    var onActivity: () -> Void = {}
    var onInteractionChanged: (Bool) -> Void = { _ in }
    func makeUIView(context: Context) -> VideoGestureView {
        let view = VideoGestureView()
        view.playerLayer.player = model.player
        view.onHoldBegan = { [weak model] in model?.beginTemporaryDoubleRate() }
        view.onHoldEnded = { [weak model] in model?.endTemporaryDoubleRate() }
        view.onSwipeBegan = { [weak model] in model?.beginHorizontalSeek() ?? false }
        view.onSwipeChanged = { [weak model] in model?.updateHorizontalSeek(translation: $0, width: $1) }
        view.onSwipeEnded = { [weak model] in model?.endHorizontalSeek() }
        view.onSwipeCancelled = { [weak model] in model?.cancelHorizontalSeek() }
        return view
    }
    func updateUIView(_ view: VideoGestureView, context: Context) {
        view.onSkip = { [weak model] in model?.skip(forward: $0); onActivity() }
        view.onSingleTap = onSingleTap
        view.onInteractionChanged = onInteractionChanged
        if view.singleTap.isEnabled != fullscreen { view.singleTap.isEnabled = fullscreen }
        view.accessibilityValue = model.stateText
        if view.playerLayer.player !== model.player { view.playerLayer.player = model.player }
        if view.cancellationID != model.gestureCancellationID {
            view.cancellationID = model.gestureCancellationID
            view.cancelGestures()
        }
    }
    static func dismantleUIView(_ view: VideoGestureView, coordinator: ()) {
        view.cancelGestures()
        view.playerLayer.player = nil
        view.onSkip = nil; view.onHoldBegan = nil; view.onHoldEnded = nil
        view.onSingleTap = nil; view.onInteractionChanged = nil
        view.onSwipeBegan = nil; view.onSwipeChanged = nil; view.onSwipeEnded = nil; view.onSwipeCancelled = nil
    }
}
