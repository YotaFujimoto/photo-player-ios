import XCTest
@testable import PhotoPlayer

final class SelectionJournalTests: XCTestCase {
    private func begin(_ journal: inout SelectionJournal, video: Int = 2) -> Int {
        journal.beginContact(video: video, scroll: "idle", receiverInScroll: true)
    }
    private func end(_ journal: inout SelectionJournal, _ contact: Int, video: Int = 2, cancelled: Bool = false) {
        journal.endContact(contact, movement: 0, cancelled: cancelled, endVideo: video, scroll: "idle")
    }
    private func accept(_ journal: inout SelectionJournal, video: Int = 2) -> Int {
        let operation = journal.actionEntered(video: video)
        journal.decision(operation, accept: true, reason: "no-app-guard")
        journal.selectionWritten(operation, reason: "Button.action")
        return operation
    }

    func testUnacceptedContactReplacesStaleSummaryWithoutErasingPreviousLifecycle() {
        var journal = SelectionJournal()
        let first = begin(&journal)
        let operation = accept(&journal)
        end(&journal, first)
        journal.appear(operation)
        journal.load(operation, event: "received")
        journal.load(operation, event: "ready")
        journal.closeRequested(operation)
        journal.bindingWrite(nil)
        journal.selectionWritten(nil, reason: "fullScreenCover.binding")
        journal.disappear(operation)
        journal.dismissed()

        let second = begin(&journal)
        end(&journal, second)
        XCTAssertEqual(journal.accepted, 1)
        XCTAssertEqual(journal.shown, 1)
        XCTAssertTrue(journal.latestContact.contains("C2 動画2 選択処理の記録なし"))
        XCTAssertTrue(journal.events.last?.contains("contact.end") == true)
        let report = journal.report(build: "6")
        XCTAssertTrue(report.contains("cover.dismiss"))
        XCTAssertTrue(report.contains("C2 V2 end=true cancel=false move=0.0pt selectionCandidate=-"))
        XCTAssertTrue(report.contains("S1 V2 contactCandidate=C1 result=終了"))
    }

    func testActionBeforeAndAfterEndBothKeepActualEventOrder() {
        for actionFirst in [true, false] {
            var journal = SelectionJournal()
            let contact = begin(&journal)
            if !actionFirst { end(&journal, contact) }
            let operation = accept(&journal)
            if actionFirst { end(&journal, contact) }
            XCTAssertEqual(journal.operations[0].contactCandidate, contact)
            XCTAssertEqual(journal.contacts[0].selection, operation)
            let actionIndex = journal.events.firstIndex { $0.contains("action.enter") }!
            let endIndex = journal.events.firstIndex { $0.contains("contact.end") }!
            XCTAssertEqual(actionIndex < endIndex, actionFirst)
        }
    }

    func testRepeatedSameVideoHasDistinctContactsAndSelections() {
        var journal = SelectionJournal()
        for _ in 0..<3 {
            let contact = begin(&journal)
            end(&journal, contact)
            _ = accept(&journal)
        }
        XCTAssertEqual(journal.contacts.map(\.id), [1, 2, 3])
        XCTAssertEqual(journal.operations.map(\.id), [1, 2, 3])
        XCTAssertEqual(journal.operations.map(\.contactCandidate), [1, 2, 3])
    }

    func testUnrelatedInputWrongVideoAndCancelledContactsAreNotMatched() {
        for reason in ["outside", "wrong-video", "cancelled"] {
            var journal = SelectionJournal()
            let contact = begin(&journal)
            end(&journal, contact, cancelled: reason == "cancelled")
            if reason == "outside" { journal.otherInputBegan() }
            let operation = accept(&journal, video: reason == "wrong-video" ? 3 : 2)
            XCTAssertEqual(operation, 1)
            XCTAssertNil(journal.operations[0].contactCandidate, reason)
            XCTAssertNil(journal.contacts[0].selection, reason)
            XCTAssertTrue(journal.report(build: "6").contains("contactMatch=none"))
        }
    }

    func testExplicitRejectionAndMissingActionHaveDifferentReports() {
        var journal = SelectionJournal()
        let contact = begin(&journal)
        let operation = journal.actionEntered(video: 2)
        journal.decision(operation, accept: false, reason: "test.guard")
        end(&journal, contact)
        XCTAssertEqual(journal.accepted, 0)
        XCTAssertTrue(journal.latestContact.contains("拒否(test.guard)"))
        XCTAssertTrue(journal.report(build: "6").contains("decision.reject reason=test.guard"))
        let unaccepted = begin(&journal, video: 3)
        end(&journal, unaccepted, video: 3)
        XCTAssertTrue(journal.latestContact.contains("選択処理の記録なし"))
    }

    func testDiagnosticGateCannotSilentlyHideNewWindowInput() {
        var journal = SelectionJournal()
        let input = journal.otherInputBegan(reason: "library-observation-gate", geometryVideo: 7)
        journal.otherInputEnded(input, movement: 0, cancelled: false)
        XCTAssertEqual(journal.contactCount, 0)
        XCTAssertEqual(journal.accepted, 0)
        let report = journal.report(build: "6")
        XCTAssertTrue(report.contains("V7 input.other.begin input=I1 reason=library-observation-gate"))
        XCTAssertTrue(report.contains("input.other.end input=I1 move=0.0pt"))
    }

    func testSelectionClearingReasonsRemainEvenIfSwiftUIObservationCoalesces() {
        var journal = SelectionJournal()
        _ = accept(&journal)
        journal.selectionWritten(nil, reason: "asset-missing-after-library-refresh")
        journal.selectionObserved(old: nil, new: nil)
        let report = journal.report(build: "6")
        XCTAssertTrue(report.contains("selection.write old=- new=S1 reason=Button.action"))
        XCTAssertTrue(report.contains("selection.write old=S1 new=- reason=asset-missing-after-library-refresh"))
        XCTAssertTrue(report.contains("selection.observed old=- new=-"))
    }

    func testLateOldPlayerCallbacksDoNotRelabelNewPlayer() {
        var journal = SelectionJournal()
        let old = accept(&journal)
        journal.appear(old)
        journal.closeRequested(old)
        journal.selectionWritten(nil, reason: "fullScreenCover.binding")
        let current = accept(&journal, video: 3)
        journal.appear(current)
        journal.disappear(old)
        journal.load(old, event: "failed")
        journal.dismissed()
        XCTAssertEqual(journal.selected, current)
        XCTAssertEqual(journal.visible, current)
        XCTAssertTrue(journal.events.last?.contains("closingCandidates=[1] phase=player selected=S2 visible=S2") == true)
        XCTAssertTrue(journal.events.contains { $0.contains("S1 V2 load.failed") })
    }

    func testReportIsBoundedAndMovementKeepsFractionalPrecision() {
        var journal = SelectionJournal()
        for number in 1...80 {
            let contact = begin(&journal, video: number)
            _ = accept(&journal, video: number)
            journal.endContact(contact, movement: 0.6, cancelled: false, endVideo: number, scroll: "idle")
        }
        XCTAssertEqual(journal.contacts.count, 16)
        XCTAssertEqual(journal.operations.count, 16)
        XCTAssertEqual(journal.events.count, 96)
        XCTAssertEqual(journal.accepted, 80)
        let report = journal.report(build: "6")
        XCTAssertTrue(report.contains("move=0.6pt"))
        XCTAssertTrue(report.contains("candidate-not-proof"))
        XCTAssertFalse(report.contains("localIdentifier"))
        XCTAssertLessThan(report.count, 24_000)
    }

    @MainActor
    func testRecordingDoesNotWaitForPublishedUIRefresh() {
        let trace = SelectionTrace()
        let operation = trace.accept(7)
        trace.selectionWritten(operation, reason: "Button.action")
        trace.appear(operation)
        trace.closeRequested(operation)
        trace.bindingWrite(nil)
        trace.selectionWritten(nil, reason: "fullScreenCover.binding")
        trace.disappear(operation)
        trace.dismissed()
        XCTAssertEqual(trace.revision, 0, "The UI publication is deferred")
        XCTAssertTrue(trace.report.contains("view.appear"))
        XCTAssertTrue(trace.report.contains("binding.write"))
        XCTAssertTrue(trace.report.contains("cover.dismiss"), "Evidence is already complete synchronously")
    }
}
