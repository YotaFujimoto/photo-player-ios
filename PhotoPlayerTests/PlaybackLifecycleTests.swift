import XCTest
import Photos
import AVFoundation
@testable import PhotoPlayer

/// Runs against the same generated, pre-authorized PhotoKit fixtures as the UI suite.
/// Exercise teardown while the boost is actually active, without a human holding a finger.
final class PlaybackLifecycleTests: XCTestCase {
    @MainActor
    func testFrameModePausesAndReturnsAtMeasuredTimeWithSelectedSpeed() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        let input = try XCTUnwrap(model.beginFrameExtraction())
        XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.selectedRate,0.25)
        let source=FrameSource(input:input)
        let times=try await source.catalogue()
        let chosen=try XCTUnwrap(times.last)
        model.returnFromFrames(at:chosen)
        try await wait { !model.isSeeking }
        XCTAssertEqual(model.player.currentTime().seconds,chosen.seconds,accuracy:0.0001)
        XCTAssertFalse(model.wantsPlayback); XCTAssertEqual(model.selectedRate,0.25)
        model.togglePlayback()
        try await wait { model.player.timeControlStatus == .playing }
        model.beginTemporaryDoubleRate(); XCTAssertEqual(model.player.rate,2)
        model.endTemporaryDoubleRate(); XCTAssertEqual(model.player.rate,0.25)
    }
    @MainActor
    func testRotationDiscardsInteractionsButKeepsIntentRateAndCommittedSeek() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        model.beginTemporaryDoubleRate()
        XCTAssertTrue(model.isTemporaryDoubleRate)
        model.cancelInteractionForRotation()
        XCTAssertFalse(model.isTemporaryDoubleRate)
        XCTAssertEqual(model.player.rate, 0.25)
        for playing in [false, true] {
            if playing { model.togglePlayback() } else { model.pause() }
            if playing { try await wait { model.player.timeControlStatus == .playing } }
            for bar in [true, false] {
                XCTAssertTrue(bar ? model.beginScrubbing() : model.beginHorizontalSeek())
                let origin = model.player.currentTime().seconds
                if bar { model.scrub(to: 20) }
                else { model.updateHorizontalSeek(translation: 100, width: 300) }
                let old = model.gestureCancellationID
                model.cancelInteractionForRotation()
                XCTAssertGreaterThan(model.gestureCancellationID, old)
                model.endScrubbing(); model.endHorizontalSeek(); model.endTemporaryDoubleRate()
                XCTAssertNil(model.seekPreview); XCTAssertFalse(model.isSeeking)
                XCTAssertEqual(model.player.currentTime().seconds, origin, accuracy: 0.15)
                XCTAssertEqual(model.wantsPlayback, playing)
                XCTAssertEqual(model.selectedRate, 0.25)
                XCTAssertEqual(model.player.rate, playing ? 0.25 : 0)
            }
        }
        model.pause()
        model.skip(forward: true)
        let committed = model.position
        XCTAssertNotNil(model.skipFeedback)
        model.cancelInteractionForRotation()
        XCTAssertNil(model.skipFeedback)
        try await wait { !model.isSeeking }
        XCTAssertEqual(model.position, committed, accuracy: 0.15)
        assertStopped(model)
    }

    @MainActor
    func testSuspendAndCloseClearAnActiveBoostWithoutLateRestart() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        model.beginTemporaryDoubleRate()
        XCTAssertTrue(model.isTemporaryDoubleRate)
        XCTAssertEqual(model.player.rate, 2)
        model.suspend()
        assertStopped(model)
        model.endTemporaryDoubleRate() // Late release after scene deactivation.
        assertStopped(model)
        XCTAssertEqual(model.selectedRate, 0.25)

        model.togglePlayback()
        try await wait { model.player.timeControlStatus == .playing }
        XCTAssertEqual(model.player.rate, 0.25)
        model.beginTemporaryDoubleRate()
        XCTAssertEqual(model.player.rate, 2)
        model.close()
        assertStopped(model)
        XCTAssertNil(model.player.currentItem)
        model.endTemporaryDoubleRate()
        assertStopped(model)
    }

    @MainActor
    func testRealPlayerQueuedSkipsPreservePausedAndPlayingRate() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.pause()
        model.setRate(0.25)
        model.beginScrubbing(); model.scrub(to: 0); model.endScrubbing()
        try await wait { !model.isSeeking }
        model.beginTemporaryDoubleRate()
        assertStopped(model)
        model.skip(forward: true)
        model.skip(forward: true)
        try await wait { !model.isSeeking }
        XCTAssertEqual(model.position, 20, accuracy: 0.1)
        assertStopped(model)
        XCTAssertEqual(model.selectedRate, 0.25)
        model.togglePlayback()
        try await wait { model.player.timeControlStatus == .playing }
        model.skip(forward: false)
        try await wait { !model.isSeeking && model.player.timeControlStatus == .playing }
        XCTAssertEqual(model.player.rate, 0.25)
        XCTAssertTrue(model.wantsPlayback)
        XCTAssertEqual(model.position, 10, accuracy: 0.5)
        for _ in 0..<3 { model.skip(forward: true) }
        try await wait { !model.isSeeking && model.player.timeControlStatus == .paused }
        XCTAssertEqual(model.position, model.duration, accuracy: 0.1)
        XCTAssertTrue(model.wantsPlayback, "A skip to the end must retain the pre-skip playback intent")
        XCTAssertFalse(model.showsPauseControl)
        model.skip(forward: false)
        try await wait { !model.isSeeking && model.player.timeControlStatus == .playing }
        XCTAssertEqual(model.player.rate, 0.25)
        XCTAssertEqual(model.position, 20, accuracy: 0.5)
        model.pause()
        for _ in 0..<4 { model.skip(forward: true) }
        try await wait { !model.isSeeking }
        XCTAssertEqual(model.position, model.duration, accuracy: 0.1)
        assertStopped(model)
    }

    @MainActor
    func testScrubReleaseCommitsLatestPositionAndPreservesPlaybackIntent() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        for playing in [false, true] {
            if playing { model.togglePlayback() } else { model.pause() }
            if playing { try await wait { model.player.timeControlStatus == .playing } }
            XCTAssertTrue(model.beginScrubbing())
            let origin = model.player.currentTime().seconds
            model.scrub(to: 8)
            XCTAssertEqual(model.displayedPosition, 8)
            XCTAssertFalse(model.isSeeking, "Finger movement must not issue AVPlayer seeks")
            XCTAssertEqual(model.player.currentTime().seconds, origin, accuracy: 0.1)
            model.scrub(to: 15)
            model.endScrubbing()
            try await wait { !model.isSeeking }
            if playing { try await wait { model.player.timeControlStatus == .playing } }
            XCTAssertEqual(model.player.currentTime().seconds, 15, accuracy: 0.25)
            XCTAssertEqual(model.player.rate, playing ? 0.25 : 0)
            XCTAssertEqual(model.wantsPlayback, playing)
            XCTAssertEqual(model.selectedRate, 0.25)
            XCTAssertNil(model.errorMessage)
        }
    }

    @MainActor
    func testHorizontalPreviewCommitsOnceAndCancelRetainsOriginAndRate() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        for playing in [false, true] {
            model.pause()
            model.beginScrubbing(); model.scrub(to: 5); model.endScrubbing()
            try await wait { !model.isSeeking }
            if playing { model.togglePlayback(); try await wait { model.player.timeControlStatus == .playing } }
            XCTAssertTrue(model.beginHorizontalSeek())
            let origin = try XCTUnwrap(model.seekPreview).origin
            for x in 1...60 { model.updateHorizontalSeek(translation: Double(x), width: 360) }
            XCTAssertEqual(model.displayedPosition, origin + 10, accuracy: 0.01)
            XCTAssertEqual(model.player.currentTime().seconds, origin, accuracy: 0.1)
            XCTAssertFalse(model.isSeeking)
            model.beginTemporaryDoubleRate()
            XCTAssertFalse(model.isTemporaryDoubleRate)
            XCTAssertFalse(model.beginScrubbing(), "Another gesture cannot replace an active preview")
            model.skip(forward: true)
            XCTAssertNil(model.skipFeedback)
            model.endHorizontalSeek()
            model.endHorizontalSeek() // A late duplicate release has no effect.
            try await wait { !model.isSeeking }
            if playing { try await wait { model.player.timeControlStatus == .playing } }
            XCTAssertEqual(model.player.currentTime().seconds, origin + 10, accuracy: 0.25)
            XCTAssertEqual(model.player.rate, playing ? 0.25 : 0)
            XCTAssertEqual(model.wantsPlayback, playing)
            XCTAssertTrue(model.beginHorizontalSeek())
            let cancelledOrigin = model.player.currentTime().seconds
            model.updateHorizontalSeek(translation: -360, width: 360)
            XCTAssertEqual(model.displayedPosition, 0)
            model.cancelHorizontalSeek(); model.endHorizontalSeek()
            XCTAssertNil(model.seekPreview)
            XCTAssertFalse(model.isSeeking)
            if playing { try await wait { model.player.timeControlStatus == .playing } }
            XCTAssertEqual(model.player.currentTime().seconds, cancelledOrigin, accuracy: 0.25)
            XCTAssertEqual(model.player.rate, playing ? 0.25 : 0)
            XCTAssertEqual(model.selectedRate, 0.25)
        }
    }

    @MainActor
    func testHeldRateBlocksSwipeAndSuspendDiscardsBothPreviewTypes() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        model.beginTemporaryDoubleRate()
        XCTAssertTrue(model.isTemporaryDoubleRate)
        XCTAssertFalse(model.beginHorizontalSeek())
        XCTAssertNil(model.seekPreview)
        model.endTemporaryDoubleRate()
        XCTAssertEqual(model.player.rate, 0.25)
        for horizontal in [false, true] {
            XCTAssertTrue(horizontal ? model.beginHorizontalSeek() : model.beginScrubbing())
            let origin = model.player.currentTime().seconds
            if horizontal { model.updateHorizontalSeek(translation: 300, width: 300) }
            else { model.scrub(to: 25) }
            model.suspend()
            model.endHorizontalSeek(); model.endScrubbing()
            XCTAssertNil(model.seekPreview)
            XCTAssertFalse(model.isSeeking)
            XCTAssertEqual(model.player.currentTime().seconds, origin, accuracy: 0.1)
            assertStopped(model)
            XCTAssertEqual(model.selectedRate, 0.25)
        }
        XCTAssertTrue(model.beginHorizontalSeek())
        model.updateHorizontalSeek(translation: 100, width: 300)
        model.close(); model.endHorizontalSeek()
        XCTAssertNil(model.seekPreview)
        XCTAssertNil(model.player.currentItem)
        assertStopped(model)
    }

    @MainActor
    func testBarAndSwipeAtEndPreservePlaybackIntentAndFeedbackUsesClampedDelta() async throws {
        let model = try makeModel()
        defer { model.close() }
        model.load()
        try await wait { model.player.timeControlStatus == .playing }
        model.setRate(0.25)
        model.beginScrubbing(); model.scrub(to: model.duration); model.endScrubbing()
        try await wait { !model.isSeeking }
        XCTAssertTrue(model.wantsPlayback)
        XCTAssertFalse(model.showsPauseControl)
        XCTAssertEqual(model.player.rate, 0)
        XCTAssertTrue(model.beginHorizontalSeek())
        model.updateHorizontalSeek(translation: -50, width: 300)
        model.endHorizontalSeek()
        try await wait { !model.isSeeking && model.player.timeControlStatus == .playing }
        XCTAssertEqual(model.player.rate, 0.25)
        model.pause()
        model.beginScrubbing(); model.scrub(to: 28); model.endScrubbing()
        try await wait { !model.isSeeking }
        model.skip(forward: true)
        XCTAssertEqual(model.skipFeedback?.text, "+2s · End")
        let firstID = model.skipFeedback?.id
        model.skip(forward: true)
        XCTAssertNotEqual(model.skipFeedback?.id, firstID)
        XCTAssertEqual(model.skipFeedback?.text, "End")
        try await wait { !model.isSeeking && model.skipFeedback == nil }
        model.skip(forward: false)
        XCTAssertNotNil(model.skipFeedback)
        model.suspend()
        XCTAssertNil(model.skipFeedback)
        assertStopped(model)
    }

    @MainActor private func makeModel() throws -> PlaybackModel {
        let assets = PHAsset.fetchAssets(with: .video, options: nil)
        let asset = assets.objects(at: IndexSet(integersIn: 0..<assets.count))
            .first { $0.pixelWidth == 320 && $0.pixelHeight == 180 }
        return PlaybackModel(asset: try XCTUnwrap(asset, "The generated PhotoKit fixture must be installed"))
    }

    @MainActor private func assertStopped(_ model: PlaybackModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(model.isTemporaryDoubleRate, file: file, line: line)
        XCTAssertFalse(model.wantsPlayback, file: file, line: line)
        XCTAssertEqual(model.player.rate, 0, file: file, line: line)
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while !condition() {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                XCTFail("AVPlayer did not reach the expected state within 15 seconds")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
