import SwiftUI
import UIKit

/// In-memory, anonymous evidence. Observing a contact never selects a video.
@MainActor
final class SelectionTrace: ObservableObject {
    @Published private(set) var revision = 0
    private(set) var journal = SelectionJournal()
    private var publicationPending = false
    var observesLibrary = true
    private var probes: [WeakProbe] = []
    private weak var window: UIWindow?
    private var observer: ContactObserver?
    private var nextProbeSerial = 0
    private var diagnosticsVisible = false

    var summary: String { "接触 \(journal.contactCount) / 受付 \(journal.accepted) / 表示 \(journal.shown) / 取得 \(journal.requested)→\(journal.received)" }
    var testValue: String {
        "contacts=\(journal.contactCount);accepted=\(journal.accepted);shown=\(journal.shown);requested=\(journal.requested);received=\(journal.received);ready=\(journal.ready)"
    }
    var report: String { journal.report(build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?") }

    // Record synchronously in delivery order. Defer only the UI publication;
    // unlike build 5, an async Task never changes the order of recorded events.
    private func changed() {
        guard !publicationPending else { return }
        publicationPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publicationPending = false
            self.revision &+= 1
        }
    }

    func accept(_ number: Int) -> Int {
        let operation = journal.actionEntered(video: number)
        journal.decision(operation, accept: true, reason: "no-app-guard")
        changed()
        return operation
    }

    func selectionWritten(_ operation: Int?, reason: String) { journal.selectionWritten(operation, reason: reason); changed() }
    func bindingWrite(_ operation: Int?) { journal.bindingWrite(operation); changed() }
    func selectionObserved(old: Int?, new: Int?) { journal.selectionObserved(old: old, new: new); changed() }

    func appear(_ operation: Int) {
        observesLibrary = false
        journal.appear(operation)
        changed()
    }

    func closeRequested(_ operation: Int) {
        observesLibrary = true
        journal.closeRequested(operation)
        changed()
    }

    func disappear(_ operation: Int) { journal.disappear(operation); changed() }

    func dismissed() {
        journal.dismissed()
        observesLibrary = journal.visible == nil
        changed()
    }

    func loadEvent(_ event: VideoLoadEvent, operation: Int) {
        let name: String = switch event {
        case .requested: "requested"
        case .received: "received"
        case .ready: "ready"
        case .failed: "failed"
        }
        journal.load(operation, event: name)
        changed()
    }

    func controlAction(_ name: String) { journal.controlAction(name); changed() }

    func diagnosticsChanged(_ visible: Bool, initial: Bool = false) {
        diagnosticsVisible = visible
        if initial { journal.diagnosticsInitialized(visible: visible) }
        else { journal.controlAction("diagnostics.toggle", detail: "visible=\(visible)") }
        changed()
    }

    fileprivate func register(_ probe: ContactProbeView) {
        probes.removeAll { $0.view == nil || $0.view === probe }
        guard probe.window != nil else { return }
        if probe.serial == 0 { nextProbeSerial += 1; probe.serial = nextProbeSerial }
        probes.append(WeakProbe(view: probe))
        // A control in a different presentation window must not move the library
        // observer away from the window that owns its cells.
        guard probe.control == nil || window == nil else { return }
        guard let candidate = probe.window, candidate !== window else { return }
        if let observer { window?.removeGestureRecognizer(observer) }
        window = candidate
        let recognizer = ContactObserver(trace: self)
        candidate.addGestureRecognizer(recognizer)
        observer = recognizer
    }

    fileprivate func unregister(_ probe: ContactProbeView) {
        probes.removeAll { $0.view == nil || $0.view === probe }
    }

    fileprivate func geometry(at point: CGPoint, in window: UIWindow, receiver: UIView?) -> ContactGeometry {
        ContactGeometry(point: point, window: window, probes: probes.compactMap(\.view), receiver: receiver)
    }

    fileprivate func contactBegan(number: Int, scroll: UIScrollView, receiver: UIView?, geometry: ContactGeometry) -> Int {
        let id = journal.beginContact(video: number, scroll: scrollSnapshot(scroll),
            receiverInScroll: receiver?.isDescendant(of: scroll) == true,
            evidence: "diagnostics=\(diagnosticsVisible) " + geometry.evidence)
        // Do not publish diagnostic-only UI changes while the finger is down.
        return id
    }

    fileprivate func otherInputBegan(reason: String, geometry: ContactGeometry?) -> Int {
        journal.otherInputBegan(reason: reason, geometryVideo: geometry?.uniqueCell?.number,
            evidence: "diagnostics=\(diagnosticsVisible) " + (geometry?.evidence ?? "geometry=unavailable"))
    }

    fileprivate func contactEnded(_ id: Int, distance: CGFloat, cancelled: Bool, endVideo: Int?, scroll: UIScrollView?) {
        journal.endContact(id, movement: Double(distance), cancelled: cancelled, endVideo: endVideo, scroll: scrollSnapshot(scroll))
        changed()
    }

    private func scrollSnapshot(_ scroll: UIScrollView?) -> String {
        guard let scroll else { return "detached" }
        return "drag:\(scroll.isDragging),decel:\(scroll.isDecelerating),pan:\(scroll.panGestureRecognizer.state.rawValue)"
    }
}

private struct WeakProbe { weak var view: ContactProbeView? }

/// No recognition, prevention, delay, or cancellation: only observes UIKit delivery.
private final class ContactObserver: UIGestureRecognizer {
    private weak var trace: SelectionTrace?
    private var contact: (id: Int, point: CGPoint)?
    private weak var scroll: UIScrollView?
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
        guard touches.count == 1, let touch = touches.first else {
            _ = trace?.otherInputBegan(reason: "multiple-touches", geometry: nil)
            state = .failed; return
        }
        guard let trace, let window = view as? UIWindow else { state = .failed; return }
        let point = touch.location(in: window)
        let geometry = trace.geometry(at: point, in: window, receiver: touch.view)
        guard trace.observesLibrary, let cell = geometry.uniqueCell, let scroll = cell.probe.scrollView else {
            let reason = !trace.observesLibrary ? "library-observation-gate" :
                !geometry.controls.isEmpty ? "control-region" : geometry.candidates.count > 1 ? "ambiguous-cells" : "outside-cell"
            _ = trace.otherInputBegan(reason: reason, geometry: geometry)
            // Keep build 5's immediate failure outside the library. In particular,
            // never remain a possible recognizer while a player control is tracking.
            // The input's beginning is recorded; no ending/cancellation is inferred.
            state = .failed; return
        }
        let id = trace.contactBegan(number: cell.number, scroll: scroll, receiver: touch.view, geometry: geometry)
        contact = (id, point)
        self.scroll = scroll
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let origin = contact?.point, let touch = touches.first else { return }
        let point = touch.location(in: view)
        distance = max(distance, hypot(point.x - origin.x, point.y - origin.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        if let contact {
            let point = touches.first?.location(in: view) ?? contact.point
            distance = max(distance, hypot(point.x - contact.point.x, point.y - contact.point.y))
            let geometry = (view as? UIWindow).flatMap { trace?.geometry(at: point, in: $0, receiver: touches.first?.view) }
            trace?.contactEnded(contact.id, distance: distance, cancelled: cancelled,
                endVideo: geometry?.uniqueCell?.number, scroll: scroll)
        }
        state = .failed
    }

    override func reset() { contact = nil; scroll = nil; distance = 0 }
}

final class ContactProbeView: UIView {
    var number = 0 { didSet { if oldValue != number { identityRevision += 1 } } }
    var control: String?
    var serial = 0
    private(set) var identityRevision = 0
    private(set) var layoutRevision = 0
    weak var trace: SelectionTrace?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func layoutSubviews() { super.layoutSubviews(); layoutRevision += 1 }
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
    var control: String? = nil
    func makeUIView(context: Context) -> ContactProbeView {
        let view = ContactProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: ContactProbeView, context: Context) {
        view.number = number
        view.control = control
        view.trace = trace
        trace.register(view)
    }
    static func dismantleUIView(_ view: ContactProbeView, coordinator: ()) {
        view.trace?.unregister(view)
        view.trace = nil
    }
}

extension View {
    func traceControl(_ name: String, trace: SelectionTrace) -> some View {
        background { ContactProbe(number: 0, trace: trace, control: name).allowsHitTesting(false) }
    }
}

struct SelectionTracePanel: View {
    @ObservedObject var trace: SelectionTrace
    let location: String
    @State private var copiedReport: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                Text(trace.summary).accessibilityIdentifier("selectionTrace.\(location)").accessibilityValue(trace.testValue)
                Text(trace.journal.latestContact)
                    .accessibilityIdentifier("selectionJournal.\(location)")
                    .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--verify-diagnostic-copy") ? trace.report : trace.journal.latestContact)
                Text(trace.journal.events.last ?? "履歴なし").truncationMode(.head)
            }.allowsHitTesting(false)
            Button(copiedReport == nil ? "診断をまとめてコピー" : "診断をコピー済み") {
                trace.controlAction("copy.\(location)")
                UIPasteboard.general.string = trace.report
                copiedReport = UIPasteboard.general.string
            }
            .accessibilityIdentifier("copySelectionTrace.\(location)")
            .traceControl("copy.\(location)", trace: trace)
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--verify-diagnostic-copy") ? (copiedReport ?? "未コピー") : "")
        }.font(.caption2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}
