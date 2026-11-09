import SwiftUI

/// A single UIControl tracking sequence handles both taps and drags.
/// The visible track uses the full width; the hit area is always 44 points high.
final class SeekBarControl: UIControl {
    var onBegin: (() -> Bool)?
    var onChange: ((Double) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var interacting = false
    private var position = 0.0
    private var duration = 0.0
    private var cancellationID = 0
    private var previousSize = CGSize.zero
    private let track = CALayer()
    private let fill = CALayer()
    private let thumb = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Playback position"
        accessibilityIdentifier = "seekSlider"
        accessibilityTraits = .adjustable
        for part in [track, fill, thumb] { layer.addSublayer(part) }
        thumb.shadowColor = UIColor.black.cgColor
        thumb.shadowOpacity = 0.15
        thumb.shadowRadius = 2
        thumb.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

    func configure(position: Double, duration: Double, enabled: Bool, cancellationID: Int) {
        if self.cancellationID != cancellationID || !enabled { cancelInteraction() }
        self.cancellationID = cancellationID
        self.duration = duration
        isEnabled = enabled
        accessibilityTraits = enabled ? .adjustable : [.adjustable, .notEnabled]
        if !interacting { self.position = PlaybackPolicy.position(position, duration: duration) }
        accessibilityValue = "\(PlaybackPolicy.clock(self.position)) of \(PlaybackPolicy.clock(duration))"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != bounds.size {
            cancelInteraction()
            previousSize = bounds.size
        }
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let x = bounds.width * CGFloat(fraction)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 0, y: bounds.midY - 2, width: bounds.width, height: 4)
        fill.frame = CGRect(x: 0, y: bounds.midY - 2, width: x, height: 4)
        thumb.frame = CGRect(x: x - 5, y: bounds.midY - 5, width: 10, height: 10)
        track.cornerRadius = 2; fill.cornerRadius = 2; thumb.cornerRadius = 5
        track.backgroundColor = UIColor.tertiaryLabel.resolvedColor(with: traitCollection).cgColor
        fill.backgroundColor = tintColor.resolvedColor(with: traitCollection).cgColor
        thumb.backgroundColor = tintColor.resolvedColor(with: traitCollection).cgColor
        layer.opacity = isEnabled ? 1 : 0.4
        CATransaction.commit()
    }

    @discardableResult func start(at x: CGFloat) -> Bool {
        guard isEnabled, duration > 0, !interacting, onBegin?() == true else { return false }
        interacting = true
        move(to: x)
        return true
    }

    func move(to x: CGFloat) {
        guard interacting else { return }
        position = SeekInteractionPolicy.barPosition(x: Double(x), width: Double(bounds.width), duration: duration)
        accessibilityValue = "\(PlaybackPolicy.clock(position)) of \(PlaybackPolicy.clock(duration))"
        onChange?(position)
        setNeedsLayout()
    }

    func finish(at x: CGFloat) {
        guard interacting else { return }
        move(to: x)
        interacting = false
        onCommit?()
    }

    func cancelInteraction() {
        guard interacting else { return }
        interacting = false
        onCancel?()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { start(at: touch.location(in: self).x) }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        move(to: touch.location(in: self).x)
        return interacting
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { finish(at: touch.location(in: self).x) } else { cancelInteraction() }
    }
    override func cancelTracking(with event: UIEvent?) { cancelInteraction() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }

    override func accessibilityIncrement() { adjust(by: 5) }
    override func accessibilityDecrement() { adjust(by: -5) }
    private func adjust(by seconds: Double) {
        guard duration > 0 else { return }
        let x = CGFloat(PlaybackPolicy.position(position + seconds, duration: duration) / duration) * bounds.width
        if start(at: x) { finish(at: x) }
    }
}

struct SeekBar: UIViewRepresentable {
    let position: Double
    let duration: Double
    let enabled: Bool
    let cancellationID: Int
    let onBegin: () -> Bool
    let onChange: (Double) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> SeekBarControl { SeekBarControl() }
    func updateUIView(_ view: SeekBarControl, context: Context) {
        view.onBegin = onBegin; view.onChange = onChange
        view.onCommit = onCommit; view.onCancel = onCancel
        view.configure(position: position, duration: duration, enabled: enabled, cancellationID: cancellationID)
    }
    static func dismantleUIView(_ view: SeekBarControl, coordinator: ()) {
        view.cancelInteraction()
        view.onBegin = nil; view.onChange = nil; view.onCommit = nil; view.onCancel = nil
    }
}
