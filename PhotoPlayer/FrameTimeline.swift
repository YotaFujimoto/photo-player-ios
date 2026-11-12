import SwiftUI

/// One cursor; the range lines and extraction ticks are drawing, not handles.
final class FrameTimelineControl: UIControl {
    var selection: FrameSelection?
    var onBegin: (() -> Bool)?
    var onMove: ((Double) -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var trackingFrame = false
    private var previousSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = true
        accessibilityIdentifier = "frameTimeline"
        accessibilityLabel = "Frame position"
        accessibilityTraits = .adjustable
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ value: FrameSelection?, enabled: Bool) {
        selection = value; isEnabled = enabled
        if !enabled { cancelFrame() }
        if let value {
            accessibilityValue = "P=\(value.position) S=\(value.start) E=\(value.end) W=0...\(value.times.count - 1)"
        }
        setNeedsDisplay()
    }
    private func x(_ index: Int, _ selection: FrameSelection) -> CGFloat {
        let duration = selection.times.last!.seconds - selection.times[0].seconds
        let fraction = duration > 0 ? (selection.times[index].seconds - selection.times[0].seconds) / duration : 0
        return 10 + CGFloat(fraction) * max(0, bounds.width - 20)
    }
    override func draw(_ rect: CGRect) {
        guard let selection, let context = UIGraphicsGetCurrentContext() else { return }
        let y = bounds.midY
        // The media controls always sit on dark local glass, independent of
        // the library/system appearance. Semantic label was black in light
        // mode and disappeared against this surface.
        context.setFillColor(UIColor.white.withAlphaComponent(0.25).cgColor)
        context.fill(CGRect(x: 10, y: y - 2, width: max(0, bounds.width - 20), height: 4))
        let start = x(selection.start, selection), end = x(selection.end, selection)
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.65).cgColor)
        context.fill(CGRect(x: start, y: y - 6, width: max(1, end - start), height: 12))
        context.setFillColor(UIColor.white.cgColor)
        for index in selection.indices { context.fill(CGRect(x: x(index, selection) - 0.5, y: y - 3, width: 1, height: 6)) }
        for edge in [start, end] { context.fill(CGRect(x: edge - 1, y: y - 10, width: 2, height: 20)) }
        context.fillEllipse(in: CGRect(x: x(selection.position, selection) - 6, y: y - 6, width: 12, height: 12))
    }
    func move(at x: CGFloat) {
        guard trackingFrame, let selection else { return }
        let ratio = min(max(Double((x - 10) / max(1, bounds.width - 20)), 0), 1)
        let start = selection.times[0].seconds
        onMove?(start + ratio * (selection.times.last!.seconds - start))
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled, onBegin?() == true else { return false }
        trackingFrame = true; move(at: touch.location(in: self).x); return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        move(at: touch.location(in: self).x); return trackingFrame
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard trackingFrame else { return }
        if let touch { move(at: touch.location(in: self).x) }
        trackingFrame = false; onEnd?()
    }
    func cancelFrame() { if trackingFrame { trackingFrame = false; onCancel?() } }
    override func cancelTracking(with event: UIEvent?) { cancelFrame() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != bounds.size { cancelFrame(); previousSize = bounds.size }
        setNeedsDisplay()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelFrame() } }
    override func accessibilityIncrement() { adjust(1) }
    override func accessibilityDecrement() { adjust(-1) }
    private func adjust(_ delta: Int) {
        guard isEnabled, let selection, onBegin?() == true else { return }
        let index = min(max(selection.position + delta, 0), selection.times.count - 1)
        onMove?(selection.times[index].seconds); onEnd?()
    }
}

struct FrameTimeline: UIViewRepresentable {
    @ObservedObject var model: FrameExtractionModel
    func makeUIView(context: Context) -> FrameTimelineControl { FrameTimelineControl(frame: .zero) }
    func updateUIView(_ view: FrameTimelineControl, context: Context) {
        view.onBegin = model.beginInteraction; view.onMove = model.move
        view.onEnd = model.finishInteraction; view.onCancel = model.cancelInteraction
        view.configure(model.selection, enabled: model.phase == .ready)
    }
    static func dismantleUIView(_ view: FrameTimelineControl, coordinator: ()) {
        view.cancelFrame()
        view.onBegin = nil; view.onMove = nil; view.onEnd = nil; view.onCancel = nil
    }
}
