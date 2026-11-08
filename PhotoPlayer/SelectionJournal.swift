import Foundation

/// Anonymous, bounded, in-memory evidence. Recording never changes app selection.
struct SelectionJournal {
    struct Contact {
        let id: Int
        let video: Int
        let input: Int
        var ended = false
        var cancelled = false
        var movement = 0.0
        var selection: Int?
    }
    struct Operation {
        let id: Int
        let video: Int
        let contactCandidate: Int?
        var decision: Bool?
        var status = "判定前"
    }

    private(set) var contacts: [Contact] = []
    private(set) var operations: [Operation] = []
    private(set) var events: [String] = []
    private(set) var contactCount = 0
    private(set) var actionCount = 0
    private(set) var accepted = 0
    private(set) var shown = 0
    private(set) var requested = 0
    private(set) var received = 0
    private(set) var ready = 0
    private(set) var selected: Int?
    private(set) var visible: Int?
    private(set) var closing: [Int] = []
    private var contactCandidate: Int?
    private var eventNumber = 0
    private var inputNumber = 0
    private let origin = ProcessInfo.processInfo.systemUptime

    var phase: String { !closing.isEmpty ? "closing" : visible != nil ? "player" : selected != nil ? "opening" : "library" }
    var state: String { "phase=\(phase) selected=\(tag(selected)) visible=\(tag(visible)) closing=\(closing)" }
    var latestContact: String {
        guard let contact = contacts.last else { return "接触なし" }
        let outcome: String
        if let id = contact.selection, let operation = operations.first(where: { $0.id == id }) {
            outcome = "S\(id)候補・\(operation.status)"
        } else { outcome = "選択処理の記録なし（現時点）" }
        return "C\(contact.id) 動画\(contact.video) \(outcome)"
    }

    @discardableResult
    mutating func beginContact(video: Int, scroll: String, receiverInScroll: Bool, evidence: String = "") -> Int {
        contactCount += 1
        inputNumber += 1
        let id = contactCount
        contacts.append(Contact(id: id, video: video, input: inputNumber))
        contacts = Array(contacts.suffix(16))
        contactCandidate = id
        append("contact.begin input=I\(inputNumber) \(state) scroll=\(scroll) receiverInScroll=\(receiverInScroll) \(evidence)", contact: id, video: video)
        return id
    }

    mutating func endContact(_ id: Int, movement: Double, cancelled: Bool, endVideo: Int?, scroll: String) {
        guard let index = contacts.firstIndex(where: { $0.id == id }) else { return }
        contacts[index].ended = true
        contacts[index].cancelled = cancelled
        contacts[index].movement = movement
        if cancelled && contactCandidate == id { contactCandidate = nil }
        append("contact.\(cancelled ? "cancel" : "end") move=\(String(format: "%.1f", movement))pt endVideo=\(endVideo.map(String.init) ?? "-") scroll=\(scroll) \(state)",
               contact: id, selection: contacts[index].selection, video: contacts[index].video)
    }

    // Record unmapped/gated window input too. Otherwise a diagnostic guard can
    // hide a new touch and leave the same stale history as build 5.
    @discardableResult
    mutating func otherInputBegan(reason: String = "outside-cell", geometryVideo: Int? = nil, evidence: String = "") -> Int {
        contactCandidate = nil
        inputNumber += 1
        append("input.other.begin input=I\(inputNumber) reason=\(reason) observation=begin-only \(state) \(evidence)", video: geometryVideo)
        return inputNumber
    }

    mutating func controlAction(_ name: String, detail: String = "") {
        // The action is certain; association with the last UIKit input is only a
        // candidate (e.g. an accessibility action may have no physical touch).
        append("control.action name=\(name) inputCandidate=\(inputNumber == 0 ? "-" : "I\(inputNumber)") association=candidate-not-proof \(detail) \(state)")
        contactCandidate = nil
    }

    mutating func diagnosticsInitialized(visible: Bool) {
        append("diagnostics.initial visible=\(visible) source=library.task \(state)")
    }

    @discardableResult
    mutating func actionEntered(video: Int) -> Int {
        actionCount += 1
        let id = actionCount
        let index = contacts.firstIndex { $0.id == contactCandidate && $0.video == video && !$0.cancelled && $0.selection == nil }
        let candidate = index.map { contacts[$0].id }
        if let index { contacts[index].selection = id }
        operations.append(Operation(id: id, video: video, contactCandidate: candidate))
        operations = Array(operations.suffix(16))
        append("action.enter source=Button.action contactMatch=\(candidate == nil ? "none" : "candidate-not-proof") \(state)", contact: candidate, selection: id, video: video)
        return id
    }

    mutating func decision(_ id: Int, accept: Bool, reason: String) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].decision = accept
        operations[index].status = accept ? "受付" : "拒否(\(reason))"
        if accept { accepted += 1 }
        append("decision.\(accept ? "accept" : "reject") reason=\(reason) \(state)", selection: id)
    }

    mutating func selectionWritten(_ id: Int?, reason: String) {
        let previous = selected
        selected = id
        if id == nil, let previous {
            update(previous, status: "選択解除(\(reason))")
            if !closing.contains(previous) { closing.append(previous) }
        } else if let id { update(id, status: "表示待ち") }
        append("selection.write old=\(tag(previous)) new=\(tag(id)) reason=\(reason) \(state)", selection: id ?? previous)
    }

    mutating func bindingWrite(_ id: Int?) {
        append("binding.write proposed=\(tag(id)) \(state)", selection: selected)
    }

    mutating func selectionObserved(old: Int?, new: Int?) {
        append("selection.observed old=\(tag(old)) new=\(tag(new)) \(state)", selection: new ?? old)
    }

    mutating func appear(_ id: Int) {
        visible = id
        shown += 1
        update(id, status: "画面表示")
        append("view.appear \(state)", selection: id)
    }

    mutating func closeRequested(_ id: Int) {
        if !closing.contains(id) { closing.append(id) }
        update(id, status: "閉じる受付")
        append("close.request \(state)", selection: id)
    }

    mutating func disappear(_ id: Int) {
        // An old player's late callback must not relabel a newer visible player.
        if visible == id { visible = nil }
        append("view.disappear \(state)", selection: id)
    }

    mutating func dismissed() {
        // SwiftUI onDismiss supplies no item. Log the candidates, do not pretend
        // the callback identifies the currently selected item.
        let candidates = closing
        if candidates.count == 1 {
            let id = candidates[0]
            if visible == id { visible = nil }
            update(id, status: "終了")
            closing.removeAll { $0 == id }
        }
        append("cover.dismiss closingCandidates=\(candidates) \(state)")
    }

    mutating func load(_ id: Int, event: String) {
        switch event {
        case "requested": requested += 1
        case "received": received += 1
        case "ready": ready += 1
        default: break
        }
        append("load.\(event) \(state)", selection: id)
    }

    func report(build: String) -> String {
        let contactLines = contacts.map { contact in
            "C\(contact.id) V\(contact.video) end=\(contact.ended) cancel=\(contact.cancelled) move=\(String(format: "%.1f", contact.movement))pt selectionCandidate=\(tag(contact.selection)) input=I\(contact.input)"
        }
        let operationLines = operations.map { "S\($0.id) V\($0.video) contactCandidate=\($0.contactCandidate.map { "C\($0)" } ?? "-") result=\($0.status)" }
        return (["PhotoPlayer build \(build)",
                 "I=ウィンドウ入力 / C=セル範囲の接触 / S=選択要求 / E=記録順 / +ms=相対記録時刻",
                 "CとSの対応は匿名動画番号と入力順からの候補。記録なしは拒否・消失の断定ではない。",
                 "point/frame/clipは接触時の同一window座標(pt)。presentationは描画中のlayer範囲（取得できる時のみ）。receiverは実際のtouch.viewのクラスと祖先。control.actionはコピー等の実処理。",
                 "直近16接触・16選択・96イベント。受付前の数値比較は不要。",
                 state, "[contacts]"] + contactLines + ["[selections]"] + operationLines + ["[events]"] + events).joined(separator: "\n")
    }

    private func tag(_ id: Int?) -> String { id.map { "S\($0)" } ?? "-" }
    private mutating func update(_ id: Int, status: String) {
        if let index = operations.firstIndex(where: { $0.id == id }) { operations[index].status = status }
    }
    private mutating func append(_ message: String, contact: Int? = nil, selection: Int? = nil, video: Int? = nil) {
        eventNumber += 1
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - origin) * 1000)
        let number = video ?? operations.first(where: { $0.id == selection })?.video
        events.append("E\(eventNumber) +\(elapsed)ms C\(contact.map(String.init) ?? "-") \(tag(selection)) V\(number.map(String.init) ?? "-") \(message)")
        events = Array(events.suffix(96))
    }
}
