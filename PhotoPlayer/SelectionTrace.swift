import SwiftUI
import UIKit

/// In-memory, anonymous evidence. Observing a contact never selects a video.
@MainActor
final class SelectionTrace: ObservableObject {
    @Published private(set) var contacts = 0
    @Published private(set) var accepted = 0
    @Published private(set) var shown = 0
    @Published private(set) var requested = 0
    @Published private(set) var received = 0
    @Published private(set) var ready = 0
    @Published private(set) var contactDescription = "接触なし"
    @Published private(set) var events: [String] = []
    @Published private(set) var isPlayerVisible = false
    var observesLibrary = true
    private var probes: [WeakProbe] = []
    private weak var window: UIWindow?
    private var observer: ContactObserver?

    var summary: String { "接触 \(contacts) / 受付 \(accepted) / 表示 \(shown) / 取得 \(requested)→\(received)" }
    var testValue: String {
        "contacts=\(contacts);accepted=\(accepted);shown=\(shown);requested=\(requested);received=\(received);ready=\(ready)"
    }

    func accept(_ number: Int) {
        accepted += 1
        events = ["動画\(number) 受付"]
    }

    func record(_ event: String) {
        events = Array((events + [event]).suffix(6))
    }

    func appear() {
        observesLibrary = false
        isPlayerVisible = true
        shown += 1
        record("画面表示")
    }

    func dismissed() {
        isPlayerVisible = false
        observesLibrary = true
        record("一覧復帰")
    }

    func loadEvent(_ event: VideoLoadEvent) {
        switch event {
        case .requested: requested += 1; record("取得開始")
        case .received: received += 1; record("取得完了")
        case .ready: ready += 1; record("再生準備完了")
        case .failed: record("取得／準備エラー")
        }
    }

    fileprivate func register(_ probe: ContactProbeView) {
        probes.removeAll { $0.view == nil || $0.view === probe }
        probes.append(WeakProbe(view: probe))
        guard let candidate = probe.window, candidate !== window else { return }
        if let observer { window?.removeGestureRecognizer(observer) }
        window = candidate
        let recognizer = ContactObserver(trace: self)
        candidate.addGestureRecognizer(recognizer)
        observer = recognizer
    }

    fileprivate func target(at point: CGPoint) -> (Int, Bool)? {
        guard observesLibrary else { return nil }
        for probe in probes.compactMap(\.view) where probe.window === window && probe.isVisibleInHierarchy {
            guard probe.convert(probe.bounds, to: window).contains(point),
                  let scroll = probe.scrollView,
                  scroll.convert(scroll.bounds, to: window).contains(point) else { continue }
            return (probe.number, scroll.isDecelerating || scroll.isDragging)
        }
        return nil
    }

    fileprivate func contact(number: Int, distance: CGFloat, scrolling: Bool, cancelled: Bool) {
        contacts += 1
        contactDescription = "動画\(number)・移動\(Int(distance))pt・\(scrolling ? "スクロール中" : "停止中")\(cancelled ? "・取消" : "")"
    }
}

private struct WeakProbe { weak var view: ContactProbeView? }

/// No recognition, prevention, delay, or cancellation: only observes UIKit delivery.
private final class ContactObserver: UIGestureRecognizer {
    private weak var trace: SelectionTrace?
    private var contact: (number: Int, point: CGPoint, scrolling: Bool)?
    private var distance: CGFloat = 0

    init(trace: SelectionTrace) {
        self.trace = trace
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first else { state = .failed; return }
        let point = touch.location(in: view)
        guard let target = trace?.target(at: point) else { state = .failed; return }
        contact = (target.0, point, target.1)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let contact, let touch = touches.first else { return }
        let point = touch.location(in: view)
        distance = max(distance, hypot(point.x - contact.point.x, point.y - contact.point.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(cancelled: true) }

    private func finish(cancelled: Bool) {
        if let contact {
            let distance = distance
            // Publish after delivery finishes; never rebuild a button mid-contact.
            Task { @MainActor [weak trace] in
                trace?.contact(number: contact.number, distance: distance,
                               scrolling: contact.scrolling, cancelled: cancelled)
            }
        }
        state = .failed
    }

    override func reset() { contact = nil; distance = 0 }
}

final class ContactProbeView: UIView {
    var number = 0
    weak var trace: SelectionTrace?
    var isVisibleInHierarchy: Bool {
        var ancestor: UIView? = self
        while let current = ancestor {
            if current.isHidden || current.alpha < 0.01 { return false }
            ancestor = current.superview
        }
        return window != nil
    }
    var scrollView: UIScrollView? {
        var ancestor = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView { return scroll }
            ancestor = current.superview
        }
        return nil
    }
    override func didMoveToWindow() { super.didMoveToWindow(); trace?.register(self) }
}

struct ContactProbe: UIViewRepresentable {
    let number: Int
    let trace: SelectionTrace
    func makeUIView(context: Context) -> ContactProbeView {
        let view = ContactProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: ContactProbeView, context: Context) {
        view.number = number
        view.trace = trace
        trace.register(view)
    }
}

struct SelectionTracePanel: View {
    @ObservedObject var trace: SelectionTrace
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trace.summary).accessibilityIdentifier("selectionTrace").accessibilityValue(trace.testValue)
            Text(trace.contactDescription)
            Text(trace.events.joined(separator: " → "))
        }.font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).allowsHitTesting(false)
    }
}
