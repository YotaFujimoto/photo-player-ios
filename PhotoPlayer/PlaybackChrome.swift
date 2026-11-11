import SwiftUI

/// UI-only state. Playback position, rate and PhotoKit ownership stay in PlaybackModel.
struct PlaybackChromeState {
    enum Blocker: Hashable { case bar, videoGesture, speedMenu, diagnostics, seeking, unavailable, button(String) }
    static let hideDelay = Duration.seconds(3)
    private(set) var isFullscreen = false
    private(set) var isActive = true
    private(set) var isPlaying = false
    private(set) var isVisible = true
    private(set) var blockers: Set<Blocker> = []
    private(set) var generation = 0
    var timeoutToken: Int? {
        isFullscreen && isActive && isPlaying && isVisible && blockers.isEmpty ? generation : nil
    }

    mutating func layout(fullscreen: Bool) {
        generation += 1
        isFullscreen = fullscreen
        isVisible = true
        blockers = []
    }
    mutating func playback(playing: Bool) {
        guard isPlaying != playing else { return }
        generation += 1
        isPlaying = playing
        if !playing { isVisible = true }
    }
    mutating func activity() { generation += 1 }
    mutating func block(_ blocker: Blocker, active: Bool) {
        let changed = active ? blockers.insert(blocker).inserted : blockers.remove(blocker) != nil
        if changed { generation += 1 }
    }
    mutating func singleTap() {
        guard isFullscreen, isActive else { return }
        generation += 1
        // Paused controls never auto-hide; an explicit tap may hide them.
        isVisible = !blockers.isEmpty ? true : !isVisible
    }
    mutating func setActive(_ active: Bool) {
        generation += 1
        isActive = active
        isVisible = true
        if !active { blockers = []; isPlaying = false }
    }
    mutating func expire(token: Int) {
        guard timeoutToken == token else { return }
        isVisible = false
        generation += 1
    }
}

@MainActor
final class PlaybackChrome: ObservableObject {
    @Published private(set) var state = PlaybackChromeState()
    private var timer: Task<Void, Never>?
    var isVisible: Bool { state.isVisible }

    func layout(fullscreen: Bool) { update { $0.layout(fullscreen: fullscreen) } }
    func playback(playing: Bool) { update { $0.playback(playing: playing) } }
    func activity() { update { $0.activity() } }
    func block(_ blocker: PlaybackChromeState.Blocker, active: Bool) { update { $0.block(blocker, active: active) } }
    func singleTap() { update { $0.singleTap() } }
    func setActive(_ active: Bool) { update { $0.setActive(active) } }

    private func update(_ change: (inout PlaybackChromeState) -> Void) {
        let oldToken = state.timeoutToken
        change(&state)
        let newToken = state.timeoutToken
        guard newToken != oldToken else { return }
        timer?.cancel()
        timer = nil
        guard let token = newToken else { return }
        timer = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: PlaybackChromeState.hideDelay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.state.expire(token: token)
        }
    }
}
