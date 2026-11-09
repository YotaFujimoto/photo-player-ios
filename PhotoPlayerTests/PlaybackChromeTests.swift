import XCTest
@testable import PhotoPlayer

final class PlaybackChromeTests: XCTestCase {
    func testEntryAndPausedControlsStayVisible() {
        var state = PlaybackChromeState()
        XCTAssertEqual(PlaybackChromeState.hideDelay, .seconds(3))
        state.layout(fullscreen: true)
        XCTAssertTrue(state.isVisible); XCTAssertNil(state.timeoutToken)
        state.singleTap()
        XCTAssertTrue(state.isVisible)
        state.playback(playing: true)
        let token = state.timeoutToken!
        state.playback(playing: false); state.expire(token: token)
        XCTAssertTrue(state.isVisible); XCTAssertNil(state.timeoutToken)
    }

    func testSingleTapAndLatestActivityOwnTheDeadline() {
        var state = PlaybackChromeState()
        state.layout(fullscreen: true); state.playback(playing: true)
        let old = state.timeoutToken!
        state.activity(); state.expire(token: old)
        XCTAssertTrue(state.isVisible)
        state.expire(token: state.timeoutToken!)
        XCTAssertFalse(state.isVisible)
        state.singleTap(); XCTAssertTrue(state.isVisible)
        state.singleTap(); XCTAssertFalse(state.isVisible)
        state.activity(); XCTAssertFalse(state.isVisible, "Hidden skip/hold/swipe must not reveal controls")
    }

    func testEveryInteractionBlocksHideAndRestartsOnlyAfterRelease() {
        let blockers: [PlaybackChromeState.Blocker] = [.bar, .videoGesture, .speedMenu, .diagnostics, .seeking, .unavailable, .button("playPause")]
        for blocker in blockers {
            var state = PlaybackChromeState()
            state.layout(fullscreen: true); state.playback(playing: true)
            let old = state.timeoutToken!
            state.block(blocker, active: true)
            XCTAssertNil(state.timeoutToken)
            state.expire(token: old); XCTAssertTrue(state.isVisible)
            state.block(blocker, active: false)
            state.expire(token: old); XCTAssertTrue(state.isVisible)
            state.expire(token: state.timeoutToken!); XCTAssertFalse(state.isVisible)
            state.block(blocker, active: true); state.block(blocker, active: false)
            XCTAssertFalse(state.isVisible); XCTAssertNil(state.timeoutToken)
        }
    }

    func testNestedInteractionsDoNotReleaseEachOther() {
        var state = PlaybackChromeState()
        state.layout(fullscreen: true); state.playback(playing: true)
        state.block(.bar, active: true); state.block(.seeking, active: true)
        state.block(.bar, active: false)
        XCTAssertNil(state.timeoutToken)
        state.block(.seeking, active: false)
        XCTAssertNotNil(state.timeoutToken)
        state.block(.speedMenu, active: true); state.playback(playing: false)
        state.block(.speedMenu, active: false)
        XCTAssertNil(state.timeoutToken); XCTAssertTrue(state.isVisible)
        state.playback(playing: true)
        state.block(.button("playPause"), active: true); state.block(.button("rateMenu"), active: true)
        state.block(.button("playPause"), active: false)
        XCTAssertNil(state.timeoutToken)
        state.block(.button("rateMenu"), active: false)
        XCTAssertNotNil(state.timeoutToken)
    }

    func testRotationBackgroundAndCloseInvalidateOldTimers() {
        var state = PlaybackChromeState()
        state.layout(fullscreen: true); state.playback(playing: true)
        let old = state.timeoutToken!
        state.layout(fullscreen: false); state.expire(token: old)
        XCTAssertTrue(state.isVisible); XCTAssertNil(state.timeoutToken)
        state.layout(fullscreen: true); state.expire(token: old)
        XCTAssertTrue(state.isVisible)
        let landscape = state.timeoutToken!
        state.block(.speedMenu, active: true); state.setActive(false)
        XCTAssertTrue(state.blockers.isEmpty); XCTAssertFalse(state.isPlaying)
        state.expire(token: landscape); state.singleTap()
        XCTAssertTrue(state.isVisible); XCTAssertNil(state.timeoutToken)
        state.setActive(true); state.playback(playing: true)
        state.expire(token: landscape); XCTAssertTrue(state.isVisible)
    }

    @MainActor func testControllerDoesNotRestartOnUnchangedPlaybackAndCancelsOnClose() {
        let chrome = PlaybackChrome()
        chrome.layout(fullscreen: true); chrome.playback(playing: true)
        let token = chrome.state.timeoutToken
        chrome.playback(playing: true)
        XCTAssertEqual(chrome.state.timeoutToken, token)
        chrome.block(.videoGesture, active: true)
        XCTAssertNil(chrome.state.timeoutToken)
        chrome.block(.videoGesture, active: false)
        XCTAssertNotEqual(chrome.state.timeoutToken, token)
        chrome.setActive(false)
        XCTAssertNil(chrome.state.timeoutToken); XCTAssertTrue(chrome.isVisible)
    }
}
