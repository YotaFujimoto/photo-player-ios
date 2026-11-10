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
    private var windows: [WeakWindow] = []
    private var nextWindow = 0
    private let session = String(UUID().uuidString.prefix(8))
    private var nextProbeSerial = 0
    private var diagnosticsVisible = false
    private var nextFrameOperation = 0
    private var frameReports: [(id: Int, video: Int, text: String)] = []

    var summary: String { "接触 \(journal.contactCount) / 受付 \(journal.accepted) / 表示 \(journal.shown) / 取得 \(journal.requested)→\(journal.received)" }
    var testValue: String {
        "contacts=\(journal.contactCount);accepted=\(journal.accepted);shown=\(journal.shown);requested=\(journal.requested);received=\(journal.received);ready=\(journal.ready)"
    }
    var report: String {
        journal.report(build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                       context: "session=\(session) source=UIApplication.sendEvent; OSからアプリへ配送される前の入力は観測できません。\n[frame extraction: last 8 operations]\n" +
                       frameReports.map { "F\($0.id) V\($0.video)\n\($0.text)" }.joined(separator: "\n"))
    }

    func beginFrameOperation(video: Int) -> Int {
        nextFrameOperation += 1
        frameReports.append((nextFrameOperation, video, "stage=opening"))
        frameReports = Array(frameReports.suffix(8))
        return nextFrameOperation
    }
    func recordFrameOperation(_ id: Int, text: String) {
        guard let index = frameReports.firstIndex(where: { $0.id == id }) else { return }
        frameReports[index].text = text
        changed()
    }

    func lifecycle(_ reason: String) {
        let live = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        journal.note("lifecycle.\(reason) windows=[\(live.map { windowDescription($0) }.joined(separator: ";"))] probes=\(probes.compactMap(\.view).count)")
    }

    func windowDescription(_ window: UIWindow?) -> String {
        guard let window else { return "none" }
        windows.removeAll { $0.window == nil }
        if !windows.contains(where: { $0.window === window }) {
            nextWindow += 1
            windows.append(WeakWindow(id: nextWindow, window: window))
        }
        let id = windows.first { $0.window === window }!.id
        return "W\(id){key=\(window.isKeyWindow),hidden=\(window.isHidden),interaction=\(window.isUserInteractionEnabled),scene=\(window.windowScene?.activationState.rawValue ?? -99)}"
    }

    func inputEntry(window: UIWindow?) -> Int {
        journal.enterInput("windowID=\(windowDescription(window)) diagnostics=\(diagnosticsVisible)")
    }

    func inputNote(_ text: String) { journal.note(text) }

    func inputEnded(_ input: Int, cancelled: Bool) {
        journal.note("input.end input=I\(input) cancelled=\(cancelled)")
    }

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
    }

    fileprivate func unregister(_ probe: ContactProbeView) {
        probes.removeAll { $0.view == nil || $0.view === probe }
    }

    func geometry(at point: CGPoint, in window: UIWindow, receiver: UIView?) -> ContactGeometry {
        ContactGeometry(point: point, window: window, probes: probes.compactMap(\.view), receiver: receiver)
    }

    func contactBegan(number: Int, scroll: UIScrollView, receiver: UIView?, geometry: ContactGeometry, input: Int) -> Int {
        let id = journal.beginContact(video: number, scroll: scrollSnapshot(scroll),
            receiverInScroll: receiver?.isDescendant(of: scroll) == true,
            evidence: "diagnostics=\(diagnosticsVisible) " + geometry.evidence, input: input)
        // Do not publish diagnostic-only UI changes while the finger is down.
        return id
    }

    func otherInputBegan(reason: String, geometry: ContactGeometry?, input: Int) -> Int {
        journal.otherInputBegan(reason: reason, geometryVideo: geometry?.uniqueCell?.number,
            evidence: "diagnostics=\(diagnosticsVisible) " + (geometry?.evidence ?? "geometry=unavailable"), input: input)
    }

    func contactEnded(_ id: Int, distance: CGFloat, cancelled: Bool, endVideo: Int?, scroll: UIScrollView?) {
        journal.endContact(id, movement: Double(distance), cancelled: cancelled, endVideo: endVideo, scroll: scrollSnapshot(scroll))
        changed()
    }

    private func scrollSnapshot(_ scroll: UIScrollView?) -> String {
        guard let scroll else { return "detached" }
        return "drag:\(scroll.isDragging),decel:\(scroll.isDecelerating),pan:\(scroll.panGestureRecognizer.state.rawValue)"
    }
}

private struct WeakProbe { weak var view: ContactProbeView? }
private struct WeakWindow { let id: Int; weak var window: UIWindow? }

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
                Text(trace.journal.events.last ?? "No events").truncationMode(.head)
            }.allowsHitTesting(false)
            Button(copiedReport == nil ? "Copy diagnostics" : "Diagnostics copied") {
                trace.controlAction("copy.\(location)")
                trace.lifecycle("copy.snapshot")
                UIPasteboard.general.string = trace.report
                copiedReport = UIPasteboard.general.string
            }
            .accessibilityIdentifier("copySelectionTrace.\(location)")
            .traceControl("copy.\(location)", trace: trace)
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--verify-diagnostic-copy") ? (copiedReport ?? "Not copied") : "")
        }.font(.caption2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}
