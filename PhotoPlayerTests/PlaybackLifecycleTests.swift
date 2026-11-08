import XCTest
import Photos
import AVFoundation
@testable import PhotoPlayer

/// Runs against the same generated, pre-authorized PhotoKit fixtures as the UI suite.
/// Exercise teardown while the boost is actually active, without a human holding a finger.
final class PlaybackLifecycleTests: XCTestCase {
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
