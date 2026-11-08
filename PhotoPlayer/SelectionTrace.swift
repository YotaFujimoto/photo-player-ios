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

    fileprivate func target(at point: CGPoint) -> (number: Int, scroll: UIScrollView)? {
        for probe in probes.compactMap(\.view) where probe.window === window && probe.isVisibleInHierarchy {
            guard probe.convert(probe.bounds, to: window).contains(point),
                  let scroll = probe.scrollView,
                  scroll.convert(scroll.bounds, to: window).contains(point) else { continue }
            return (probe.number, scroll)
        }
        return nil
    }

    fileprivate func contactBegan(number: Int, scroll: UIScrollView, receiver: UIView?) -> Int {
        let id = journal.beginContact(video: number, scroll: scrollSnapshot(scroll),
            receiverInScroll: receiver?.isDescendant(of: scroll) == true)
        // Do not publish diagnostic-only UI changes while the finger is down.
        return id
    }

    fileprivate func otherInputBegan(reason: String, geometryVideo: Int?) -> Int {
        journal.otherInputBegan(reason: reason, geometryVideo: geometryVideo)
    }

    fileprivate func otherInputEnded(_ id: Int, distance: CGFloat, cancelled: Bool) {
        journal.otherInputEnded(id, movement: Double(distance), cancelled: cancelled)
        changed()
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
    private var otherInput: (id: Int, point: CGPoint)?
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
            if let id = trace?.otherInputBegan(reason: "multiple-touches", geometryVideo: nil) {
                trace?.otherInputEnded(id, distance: 0, cancelled: true)
            }
            state = .failed; return
        }
        let point = touch.location(in: view)
        guard let trace else { state = .failed; return }
        let target = trace.target(at: point)
        guard trace.observesLibrary, let target else {
            let id = trace.otherInputBegan(reason: trace.observesLibrary ? "outside-cell" : "library-observation-gate", geometryVideo: target?.number)
            otherInput = (id, point)
            return
        }
        let id = trace.contactBegan(number: target.number, scroll: target.scroll, receiver: touch.view)
        contact = (id, point)
        scroll = target.scroll
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let origin = contact?.point ?? otherInput?.point, let touch = touches.first else { return }
        let point = touch.location(in: view)
        distance = max(distance, hypot(point.x - origin.x, point.y - origin.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        if let contact {
            let point = touches.first?.location(in: view) ?? contact.point
            distance = max(distance, hypot(point.x - contact.point.x, point.y - contact.point.y))
            trace?.contactEnded(contact.id, distance: distance, cancelled: cancelled,
                endVideo: trace?.target(at: point)?.number, scroll: scroll)
        } else if let otherInput {
            let point = touches.first?.location(in: view) ?? otherInput.point
            distance = max(distance, hypot(point.x - otherInput.point.x, point.y - otherInput.point.y))
            trace?.otherInputEnded(otherInput.id, distance: distance, cancelled: cancelled)
        }
        state = .failed
    }

    override func reset() { contact = nil; otherInput = nil; scroll = nil; distance = 0 }
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
                UIPasteboard.general.string = trace.report
                copiedReport = UIPasteboard.general.string
            }
            .accessibilityIdentifier("copySelectionTrace.\(location)")
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--verify-diagnostic-copy") ? (copiedReport ?? "未コピー") : "")
        }.font(.caption2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}
