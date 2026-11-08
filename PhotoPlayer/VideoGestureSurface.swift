import SwiftUI
import AVFoundation

/// Recognizers belong only to the video view, never the window or controls.
final class VideoGestureView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onSkip: ((Bool) -> Void)?
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?
    private(set) var doubleTap = UITapGestureRecognizer()
    private(set) var hold = UILongPressGestureRecognizer()
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(tapped(_:)))
        hold.addTarget(self, action: #selector(held(_:)))
        // Short taps make the standard long-press recognizer fail naturally.
        // A held press and a double tap cannot both act on the same contact.
        doubleTap.require(toFail: hold)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(hold)
        isAccessibilityElement = true
        accessibilityLabel = "Video"
        accessibilityIdentifier = "videoSurface"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Skip back 10 seconds", target: self, selector: #selector(skipBack)),
            UIAccessibilityCustomAction(name: "Skip forward 10 seconds", target: self, selector: #selector(skipForward))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onSkip?(recognizer.location(in: self).x >= bounds.midX)
    }

    @objc func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: onHoldBegan?()
        case .changed:
            if !bounds.contains(recognizer.location(in: self)) { cancelHold() }
        case .ended, .cancelled, .failed: onHoldEnded?()
        default: break
        }
    }

    func cancelHold() {
        onHoldEnded?()
        hold.isEnabled = false
        hold.isEnabled = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelHold() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != bounds.size { cancelHold(); lastSize = bounds.size }
    }

    @objc private func skipBack() -> Bool { onSkip?(false); return true }
    @objc private func skipForward() -> Bool { onSkip?(true); return true }
}

struct PlayerSurface: UIViewRepresentable {
    let model: PlaybackModel
    func makeUIView(context: Context) -> VideoGestureView {
        let view = VideoGestureView()
        view.playerLayer.player = model.player
        view.onSkip = { [weak model] in model?.skip(forward: $0) }
        view.onHoldBegan = { [weak model] in model?.beginTemporaryDoubleRate() }
        view.onHoldEnded = { [weak model] in model?.endTemporaryDoubleRate() }
        return view
    }
    func updateUIView(_ view: VideoGestureView, context: Context) {
        if view.playerLayer.player !== model.player { view.playerLayer.player = model.player }
    }
    static func dismantleUIView(_ view: VideoGestureView, coordinator: ()) {
        view.cancelHold()
        view.playerLayer.player = nil
        view.onSkip = nil; view.onHoldBegan = nil; view.onHoldEnded = nil
    }
}
