import XCTest
@testable import PhotoPlayer

final class PlaybackPolicyTests: XCTestCase {
    func testTenSecondSkipsClampAtBothEndsIncludingShortVideos() {
        XCTAssertEqual(PlaybackPolicy.skip(from: 42, forward: false, duration: 7200), 32)
        XCTAssertEqual(PlaybackPolicy.skip(from: 42, forward: true, duration: 7200), 52)
        XCTAssertEqual(PlaybackPolicy.skip(from: 4, forward: false, duration: 7200), 0)
        XCTAssertEqual(PlaybackPolicy.skip(from: 7198, forward: true, duration: 7200), 7200)
        XCTAssertEqual(PlaybackPolicy.skip(from: 0, forward: true, duration: 3), 3)
        XCTAssertEqual(PlaybackPolicy.skip(from: 3, forward: false, duration: 3), 0)
        XCTAssertEqual(PlaybackPolicy.skip(from: .nan, forward: true, duration: 0), 0)
    }

    func testHoldRestoresEverySelectedRateWithoutChangingIt() {
        for rate in PlaybackPolicy.rates {
            var speed = PlaybackSpeed()
            speed.select(rate)
            speed.beginHold(isPlaying: true)
            XCTAssertEqual(speed.effective, 2)
            XCTAssertEqual(speed.selected, rate)
            speed.endHold()
            speed.endHold() // UIKit cancellation and scene teardown may both arrive.
            XCTAssertFalse(speed.isBoosting)
            XCTAssertEqual(speed.effective, rate)
        }
    }

    func testPausedHoldDoesNotActivateAndExplicitRateChangeCancelsHold() {
        var speed = PlaybackSpeed()
        speed.select(0.25)
        speed.beginHold(isPlaying: false)
        XCTAssertFalse(speed.isBoosting)
        XCTAssertEqual(speed.effective, 0.25)
        speed.beginHold(isPlaying: true)
        speed.select(1.5)
        XCTAssertFalse(speed.isBoosting)
        XCTAssertEqual(speed.effective, 1.5)
    }

    func testRapidSkipsAccumulateTargetsWhileOnlyLatestPendingSeekRuns() {
        var queue = SeekQueue()
        var target = 5.0
        for _ in 0..<3 {
            target = PlaybackPolicy.skip(from: target, forward: true, duration: 30)
            _ = queue.enqueue(SeekRequest(seconds: target, exact: true))
        }
        XCTAssertEqual(queue.active?.seconds, 15)
        XCTAssertEqual(queue.finish()?.seconds, 30)
        XCTAssertNil(queue.finish())
    }

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
