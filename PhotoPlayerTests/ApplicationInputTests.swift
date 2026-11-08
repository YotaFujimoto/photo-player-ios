import XCTest
import SwiftUI
@testable import PhotoPlayer

final class ApplicationInputTests: XCTestCase {
    @MainActor
    func testEntryPrecedesWindowGuardAndForwarding() {
        let trace = SelectionTrace()
        let input = ApplicationInput(trace: trace)
        let finger = NSObject()
        let sample = InputSample(key: ObjectIdentifier(finger), phase: .began, point: .zero, window: nil, receiver: nil)
        var forwards = 0
        input.dispatch([sample]) {
            forwards += 1
            XCTAssertTrue(trace.report.contains("input.entry input=I1 source=UIApplication.sendEvent windowID=none"))
            XCTAssertTrue(trace.report.contains("input=I1 reason=no-window"))
        }
        XCTAssertEqual(forwards, 1)
        XCTAssertEqual(trace.journal.contactCount, 0)
    }

    @MainActor
    func testTwoWindowsAreObservedWithoutMovingARecognizer() {
        let trace = SelectionTrace()
        let input = ApplicationInput(trace: trace)
        let first = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let second = UIWindow(frame: first.frame)
        let a = NSObject(), b = NSObject()
        input.dispatch([
            InputSample(key: ObjectIdentifier(a), phase: .began, point: .zero, window: first, receiver: first),
            InputSample(key: ObjectIdentifier(b), phase: .began, point: .zero, window: second, receiver: second)
        ]) {}
        XCTAssertTrue(trace.report.contains("input.entry input=I1 source=UIApplication.sendEvent windowID=W1{"))
        XCTAssertTrue(trace.report.contains("input.entry input=I2 source=UIApplication.sendEvent windowID=W2{"))
        XCTAssertTrue((first.gestureRecognizers ?? []).isEmpty)
        XCTAssertTrue((second.gestureRecognizers ?? []).isEmpty)
    }

    @MainActor
    func testCloseContactDoesNotSuppressOverlappingCellContactWithDiagnosticsOff() {
        let trace = SelectionTrace()
        let input = ApplicationInput(trace: trace)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.isHidden = false
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: window.bounds)
        window.addSubview(scroll)
        let probe = ContactProbeView(frame: CGRect(x: 16, y: 467, width: 166, height: 130))
        probe.number = 5; probe.trace = trace
        scroll.addSubview(probe)
        let closingFinger = NSObject(), nextFinger = NSObject()
        trace.observesLibrary = false
        input.dispatch([InputSample(key: ObjectIdentifier(closingFinger), phase: .began,
                                    point: CGPoint(x: 40, y: 70), window: window, receiver: window)]) {}
        trace.observesLibrary = true
        let sample = InputSample(key: ObjectIdentifier(nextFinger), phase: .began,
                                 point: CGPoint(x: 90, y: 520), window: window, receiver: scroll)
        input.dispatch([sample]) {}
        XCTAssertTrue(trace.report.contains("V5 contact.begin input=I2"))
        XCTAssertTrue(trace.report.contains("diagnostics=false"))
        XCTAssertEqual(trace.journal.contactCount, 1)
        XCTAssertTrue((window.gestureRecognizers ?? []).isEmpty, "Registering a probe must not install an input competitor")
        input.dispatch([InputSample(key: sample.key, phase: .ended, point: sample.point, window: window, receiver: scroll)]) {}
        XCTAssertEqual(trace.journal.contacts.first?.ended, true)
    }

    @MainActor
    func testLifecycleAndTabNotesDoNotResetInputHistory() {
        let trace = SelectionTrace()
        let input = ApplicationInput(trace: trace)
        let finger = NSObject()
        func send(_ phase: UITouch.Phase) {
            input.dispatch([InputSample(key: ObjectIdentifier(finger), phase: phase, point: .zero, window: nil, receiver: nil)]) {}
        }
        send(.began); send(.ended)
        let state = AppSceneState(trace: trace)
        state.transition(.background, reason: "scene.background")
        XCTAssertEqual(state.phase, .background)
        trace.lifecycle("tab.counter")
        trace.lifecycle("tab.library")
        state.transition(.active, reason: "scene.active")
        XCTAssertEqual(state.phase, .active)
        trace.diagnosticsChanged(true)
        send(.began); send(.ended)
        XCTAssertTrue(trace.report.contains("input.entry input=I1"))
        XCTAssertTrue(trace.report.contains("input.entry input=I2"))
        XCTAssertTrue(trace.report.contains("lifecycle.scene.background"))
        XCTAssertTrue(trace.report.contains("lifecycle.tab.library"))
    }

    @MainActor
    func testForwardingIsExactlyOnceWithMonitorEnabledOrDisabled() {
        for enabled in [true, false] {
            let trace = SelectionTrace()
            let input = ApplicationInput(trace: trace, enabled: enabled)
            let finger = NSObject()
            var forwards = 0
            var sampleReads = 0
            func samples() -> [InputSample] { sampleReads += 1; return [] }
            input.dispatch(samples()) { forwards += 1 }
            XCTAssertEqual(sampleReads, enabled ? 1 : 0, "Disabled monitoring must bypass touch inspection too")
            for phase in [UITouch.Phase.began, .stationary, .moved, .ended, .cancelled] {
                input.dispatch([InputSample(key: ObjectIdentifier(finger), phase: phase, point: .zero, window: nil, receiver: nil)]) { forwards += 1 }
            }
            XCTAssertEqual(forwards, 6)
            XCTAssertEqual(trace.report.contains("input.entry"), enabled)
            if enabled { XCTAssertTrue(trace.report.contains("input.missing-begin")) }
        }
    }

    @MainActor
    func testRepeatedDeliveryIsExplicitAndDoesNotInventAnotherInput() {
        let trace = SelectionTrace()
        let input = ApplicationInput(trace: trace)
        let finger = NSObject()
        let sample = InputSample(key: ObjectIdentifier(finger), phase: .began, point: .zero, window: nil, receiver: nil)
        var forwards = 0
        input.dispatch([sample]) { forwards += 1 }
        input.dispatch([sample]) { forwards += 1 }
        XCTAssertEqual(forwards, 2)
        XCTAssertTrue(trace.report.contains("input.duplicate-begin input=I1"))
        XCTAssertFalse(trace.report.contains("input=I2"))
        let reused = InputSample(key: sample.key, phase: .began, point: .zero, window: nil, receiver: nil, timestamp: sample.timestamp + 1)
        input.dispatch([reused]) { forwards += 1 }
        XCTAssertEqual(forwards, 3)
        XCTAssertTrue(trace.report.contains("input.replaced-missing-end previous=I1"))
        XCTAssertTrue(trace.report.contains("input.entry input=I2"))
    }
}
