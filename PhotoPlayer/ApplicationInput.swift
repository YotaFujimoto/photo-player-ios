import UIKit

/// Value adapter lets tests exercise the dispatch boundary without manufacturing
/// UIKit events or using private touch injection APIs. Object identities stay local.
@MainActor
struct InputSample {
    let key: ObjectIdentifier
    let phase: UITouch.Phase
    let point: CGPoint
    let window: UIWindow?
    let receiver: UIView?
    let timestamp: TimeInterval

    init(key: ObjectIdentifier, phase: UITouch.Phase, point: CGPoint, window: UIWindow?, receiver: UIView?, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.key = key; self.phase = phase; self.point = point; self.window = window; self.receiver = receiver
        self.timestamp = timestamp
    }
    init(touch: UITouch) {
        self.init(key: ObjectIdentifier(touch), phase: touch.phase, point: touch.location(in: touch.window),
                  window: touch.window, receiver: touch.view, timestamp: touch.timestamp)
    }
}

@MainActor
final class ApplicationInput {
    private final class Active {
        let input: Int
        let contact: Int?
        let origin: CGPoint
        let beganAt: TimeInterval
        weak var scroll: UIScrollView?
        var distance: CGFloat = 0
        init(input: Int, contact: Int?, origin: CGPoint, scroll: UIScrollView?, beganAt: TimeInterval) {
            self.input = input; self.contact = contact; self.origin = origin; self.scroll = scroll
            self.beganAt = beganAt
        }
    }
    private let trace: SelectionTrace
    private let enabled: Bool
    private var active: [ObjectIdentifier: Active] = [:]

    init(trace: SelectionTrace, enabled: Bool = true) {
        self.trace = trace; self.enabled = enabled
        trace.inputNote("monitor.start enabled=\(enabled) boundary=UIApplication.sendEvent gestures=0")
    }

    func dispatch(_ samples: [InputSample], forward: () -> Void) {
        if enabled { for sample in samples { observe(sample) } }
        // Unconditional, exactly once, including no-touch events, missing windows,
        // multiple touches, diagnostics off, player controls, and unknown phases.
        forward()
    }

    private func observe(_ sample: InputSample) {
        switch sample.phase {
        case .began:
            if let previous = active[sample.key] {
                if previous.beganAt == sample.timestamp {
                    trace.inputNote("input.duplicate-begin input=I\(previous.input)")
                    return
                }
                // An ended event can be absent across OS interruption. A reused
                // UITouch address must never hide a later, genuinely new begin.
                trace.inputNote("input.replaced-missing-end previous=I\(previous.input)")
            }
            let input = trace.inputEntry(window: sample.window)
            let geometry = sample.window.map { trace.geometry(at: sample.point, in: $0, receiver: sample.receiver) }
            let cell = geometry?.contactCell
            var contact: Int?
            if trace.observesLibrary, let cell, let scroll = cell.probe.scrollView, let geometry {
                contact = trace.contactBegan(number: cell.number, scroll: scroll, receiver: sample.receiver,
                                             geometry: geometry, input: input)
            } else {
                let reason = sample.window == nil ? "no-window" : !trace.observesLibrary ? "library-observation-gate" :
                    geometry?.controls.isEmpty == false ? "control-region" : (geometry?.candidates.count ?? 0) > 1 ? "ambiguous-cells" :
                    geometry?.uniqueCell != nil ? "receiver-outside-cell-scroll" : "outside-cell"
                _ = trace.otherInputBegan(reason: reason, geometry: geometry, input: input)
            }
            if active.count >= 16, let oldest = active.min(by: { $0.value.input < $1.value.input }) {
                trace.inputNote("input.tracking-limit previous=I\(oldest.value.input)")
                active.removeValue(forKey: oldest.key)
            }
            active[sample.key] = Active(input: input, contact: contact, origin: sample.point,
                                        scroll: cell?.probe.scrollView, beganAt: sample.timestamp)
        case .moved, .ended, .cancelled:
            guard let current = active[sample.key] else {
                trace.inputNote("input.missing-begin phase=\(sample.phase.rawValue) windowID=\(trace.windowDescription(sample.window))")
                return
            }
            current.distance = max(current.distance, hypot(sample.point.x - current.origin.x, sample.point.y - current.origin.y))
            if sample.phase == .ended || sample.phase == .cancelled {
                if let contact = current.contact {
                    let geometry = sample.window.map { trace.geometry(at: sample.point, in: $0, receiver: sample.receiver) }
                    trace.contactEnded(contact, distance: current.distance, cancelled: sample.phase == .cancelled,
                                       endVideo: geometry?.uniqueCell?.number, scroll: current.scroll)
                } else { trace.inputEnded(current.input, cancelled: sample.phase == .cancelled) }
                active.removeValue(forKey: sample.key)
            }
        case .stationary: break
        @unknown default: trace.inputNote("input.unknown-phase")
        }
    }
}
