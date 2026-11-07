import XCTest
@testable import PhotoPlayer

final class PlaybackPolicyTests: XCTestCase {
    func testLongVideoSeekAndInvalidTimes() {
        XCTAssertEqual(PlaybackPolicy.position(7190, duration: 7200), 7190)
        XCTAssertEqual(PlaybackPolicy.position(9000, duration: 7200), 7200)
        XCTAssertEqual(PlaybackPolicy.position(-5, duration: 7200), 0)
        XCTAssertEqual(PlaybackPolicy.position(.nan, duration: 7200), 0)
        XCTAssertEqual(PlaybackPolicy.position(10, duration: .infinity), 0)
        XCTAssertEqual(PlaybackPolicy.clock(7201), "2:00:01")
        XCTAssertEqual(PlaybackPolicy.clock(.nan), "--:--")
    }

    func testOnlyLatestPendingSeekRuns() {
        var queue = SeekQueue()
        let first = SeekRequest(seconds: 100, exact: false)
        let last = SeekRequest(seconds: 6000, exact: true)
        XCTAssertEqual(queue.enqueue(first), first)
        XCTAssertNil(queue.enqueue(SeekRequest(seconds: 2000, exact: false)))
        XCTAssertNil(queue.enqueue(last))
        XCTAssertEqual(queue.finish(), last)
        XCTAssertTrue(queue.isBusy)
        XCTAssertNil(queue.finish())
        XCTAssertFalse(queue.isBusy)
    }

    func testClosingDropsPendingSeeks() {
        var queue = SeekQueue()
        _ = queue.enqueue(SeekRequest(seconds: 5, exact: false))
        _ = queue.enqueue(SeekRequest(seconds: 15, exact: true))
        queue.cancel()
        XCTAssertNil(queue.finish())
        XCTAssertFalse(queue.isBusy)
    }

    func testCancelledCloudRequestCannotDeliverLateProgressOrResult() {
        var gate = RequestGate()
        let cancelled = gate.begin()
        XCTAssertTrue(gate.accepts(cancelled))
        gate.cancel()
        XCTAssertFalse(gate.accepts(cancelled))
        XCTAssertFalse(gate.finish(cancelled))
    }

    func testRetryRejectsOldRequestAndDuplicateCompletions() {
        var gate = RequestGate()
        let old = gate.begin()
        let current = gate.begin()
        XCTAssertFalse(gate.finish(old))
        XCTAssertTrue(gate.accepts(current))
        XCTAssertTrue(gate.finish(current))
        XCTAssertFalse(gate.finish(current))
        XCTAssertFalse(gate.accepts(current))
    }

    func testDiagnosticsDoNotIncludeErrorDescriptionsOrFilePaths() {
        let error = NSError(domain: "PHPhotosErrorDomain", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "private-name.mov /private/video/file"])
        XCTAssertEqual(PlaybackPolicy.errorCode(error), "PHPhotosErrorDomain / 42")
    }
}
