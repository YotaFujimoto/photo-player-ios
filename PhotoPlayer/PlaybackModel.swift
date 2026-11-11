@preconcurrency import AVFoundation
@preconcurrency import Photos
import SwiftUI

// The PhotoKit callback transfers the item to MainActor; it is never used on that queue again.
private struct PlayerItemResult: @unchecked Sendable {
    let item: AVPlayerItem?
    let cancelled: Bool
    let errorCode: String?
}

enum VideoLoadEvent { case requested, received, ready, failed }

@MainActor
final class PlaybackModel: ObservableObject {
    var onLoadEvent: ((VideoLoadEvent) -> Void)?
    private var heldResult: (UUID, PlayerItemResult)?
    @Published private(set) var isTestResultHeld = false
    let player = AVPlayer()
    let asset: PHAsset
    @Published private(set) var isLoading = false
    @Published private(set) var isReady = false
    @Published private(set) var hasDownloadProgress = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var seekPreview: SeekPreview?
    @Published private(set) var skipFeedback: SkipFeedback?
    @Published private(set) var gestureCancellationID = 0
    var displayedPosition: Double { seekPreview?.target ?? position }
    @Published private var speed = PlaybackSpeed()
    var selectedRate: Float { speed.selected }
    var isTemporaryDoubleRate: Bool { speed.isBoosting }
    var showsPauseControl: Bool { wantsPlayback && !isAtSkippedEnd }
    @Published private(set) var actualRate: Float = 0
    @Published private(set) var wantsPlayback = false
    @Published private(set) var canPlaySlow = false
    @Published private(set) var isSeeking = false
    @Published private(set) var stateText = "Loading…"
    @Published private(set) var pictureSize = CGSize.zero
    @Published private(set) var hdrDescription = "Checking…"
    @Published private(set) var bufferedUntil = 0.0
    @Published private(set) var voicePitch = false

    private let manager = PHImageManager()
    private var requestID: PHImageRequestID?
    private var requestGate = RequestGate()
    private var session = UUID()
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var seekQueue = SeekQueue()
    private var keepsPlaybackAtSkippedEnd = false
    private var isAtSkippedEnd: Bool { keepsPlaybackAtSkippedEnd && duration > 0 && position >= duration }
    private var feedbackTask: Task<Void, Never>?
    private var audioActive = false
    private var audioActivating = false
    private var audioRequest = UUID()

    init(asset: PHAsset) { self.asset = asset }

    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PlaybackModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func trace(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("--playback-diagnostics") else { return }
        print("Playback: tick=\(ProcessInfo.processInfo.systemUptime) \(event), time=\(position), selected=\(selectedRate), actual=\(player.rate), state=\(stateText)")
    }

    func load() {
        close()
        errorMessage = nil
        duration = asset.duration
        position = 0
        progress = 0
        hasDownloadProgress = false
        hdrDescription = "Checking…"
        speed = PlaybackSpeed()
        stateText = "Loading…"
        isLoading = true
        wantsPlayback = true
        let token = requestGate.begin()
        onLoadEvent?(.requested)
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { @Sendable [weak self] fraction, error, _, _ in
            let errorCode = error.map { PlaybackPolicy.errorCode($0) }
            Task { @MainActor in
                guard let self, self.requestGate.accepts(token) else { return }
                // PhotoKit can report progress for local assets as well as iCloud downloads.
                self.hasDownloadProgress = true
                if fraction.isFinite { self.progress = max(self.progress, min(max(fraction, 0), 1)) }
                if let errorCode { self.failDownload("Download failed (\(errorCode)). Check your connection and retry.") }
            }
        }
        requestID = manager.requestPlayerItem(forVideo: asset, options: options) { @Sendable [weak self] item, info in
            let result = PlayerItemResult(item: item,
                cancelled: info?[PHImageCancelledKey] as? Bool == true,
                errorCode: (info?[PHImageErrorKey] as? Error).map { PlaybackPolicy.errorCode($0) })
            Task { @MainActor in
                guard let self, self.requestGate.accepts(token) else { return }
                if ProcessInfo.processInfo.arguments.contains("--hold-player-result") {
                    self.heldResult = (token, result)
                    self.isTestResultHeld = true
                    return
                }
                self.receive(result, token: token)
            }
        }
    }

    private func receive(_ result: PlayerItemResult, token: UUID) {
        guard requestGate.finish(token) else { return }
        requestID = nil
        isLoading = false
        if result.cancelled {
            wantsPlayback = false
            errorMessage = "Download cancelled."
            onLoadEvent?(.failed)
        } else if let item = result.item {
            progress = 1
            onLoadEvent?(.received)
            install(item)
        } else {
            wantsPlayback = false
            errorMessage = "Video unavailable (\(result.errorCode ?? "Unavailable")). Check Photos access and your connection."
            onLoadEvent?(.failed)
        }
    }

    // Deterministic CI gate, not a production delay or an opening workaround.
    func releaseTestResult() {
        guard let (token, result) = heldResult else { return }
        heldResult = nil
        isTestResultHeld = false
        receive(result, token: token)
    }

    func cancelLoading() { failDownload("Download cancelled.") }

    private func failDownload(_ message: String) {
        heldResult = nil
        isTestResultHeld = false
        onLoadEvent?(.failed)
        requestGate.cancel()
        if let requestID { manager.cancelImageRequest(requestID) }
        requestID = nil
        isLoading = false
        wantsPlayback = false
        errorMessage = message
        stateText = "Download stopped"
    }

    private func install(_ item: AVPlayerItem) {
        let currentSession = session
        item.asset.loadTracks(withMediaCharacteristic: .containsHDRVideo) { @Sendable [weak self] tracks, _ in
            let description = tracks.map { $0.isEmpty ? "No" : "Yes" } ?? "Unknown"
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                self.hdrDescription = description
            }
        }
        item.audioTimePitchAlgorithm = voicePitch ? .timeDomain : .spectral
        player.replaceCurrentItem(with: item)
        observations = [
            item.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.refresh(ifSession: currentSession) }
            },
            player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.refresh(ifSession: currentSession) }
            },
            player.observe(\.rate, options: [.new]) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.refresh(ifSession: currentSession) }
            }
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) {
            @Sendable [weak self] _ in Task { @MainActor in self?.refresh(ifSession: currentSession) }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) {
            [weak self] _ in Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                // A queued seek can make an earlier end notification obsolete.
                guard !self.seekQueue.isBusy,
                      self.player.currentTime().seconds >= self.duration - 0.05 else { return }
                if self.keepsPlaybackAtSkippedEnd && self.wantsPlayback { return }
                self.pause()
                self.position = self.duration
                self.stateText = "Ended"
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) {
            [weak self] note in
            let code = PlaybackPolicy.errorCode(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                self.pause()
                self.errorMessage = "Playback failed (\(code))."
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
            [weak self] _ in Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                self.pause()
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) {
            [weak self] note in
            let disconnected = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if disconnected { Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                self.pause()
            } }
        })
    }

    private func refresh(ifSession currentSession: UUID) {
        guard session == currentSession, let item = player.currentItem else { return }
        if item.status == .failed {
            if errorMessage == nil { onLoadEvent?(.failed) }
            pause()
            isReady = false
            errorMessage = "Cannot play video (\(PlaybackPolicy.errorCode(item.error)))."
            stateText = "Error"
            return
        }
        let firstReady = !isReady && item.status == .readyToPlay
        if firstReady { onLoadEvent?(.ready) }
        assign(\.isReady, item.status == .readyToPlay)
        assign(\.canPlaySlow, isReady && item.canPlaySlowForward)
        let seconds = item.duration.seconds
        if seconds.isFinite && seconds > 0 { assign(\.duration, seconds) }
        assign(\.pictureSize, item.presentationSize)
        if seekPreview == nil && !seekQueue.isBusy { assign(\.position, PlaybackPolicy.position(player.currentTime().seconds, duration: duration)) }
        assign(\.bufferedUntil, item.loadedTimeRanges.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds }
            .filter(\.isFinite).max() ?? 0)
        assign(\.actualRate, player.rate)
        let newState: String
        if !isReady { newState = "Loading…" }
        else if isSeeking { newState = "Seeking…" }
        else {
            switch player.timeControlStatus {
            case .playing: newState = "Playing"
            case .waitingToPlayAtSpecifiedRate: newState = "Buffering…"
            case .paused: newState = position >= duration && duration > 0 ? "Ended" : "Paused"
            @unknown default: newState = "Waiting…"
            }
        }
        assign(\.stateText, newState)
        if firstReady && wantsPlayback { resumeIfNeeded() }
    }

    func togglePlayback() {
        if isAtSkippedEnd {
            keepsPlaybackAtSkippedEnd = false
            wantsPlayback = true
            enqueueSeek(0, exact: true)
        } else if wantsPlayback { pause() }
        else {
            wantsPlayback = true
            if duration > 0 && position >= duration - 0.1 { enqueueSeek(0, exact: true) }
            else { resumeIfNeeded() }
        }
    }

    func pause() {
        seekPreview = nil
        gestureCancellationID += 1
        keepsPlaybackAtSkippedEnd = false
        speed.endHold()
        assign(\.wantsPlayback, false)
        if player.timeControlStatus != .paused || player.rate != 0 { player.pause() }
        assign(\.actualRate, 0)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func resumeIfNeeded() {
        guard wantsPlayback, isReady, seekPreview == nil, !seekQueue.isBusy else { return }
        // At the boundary no frames remain. Retain the pre-skip play intent so
        // a subsequent backward skip resumes, without running beyond duration.
        if isAtSkippedEnd {
            player.pause()
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        guard selectedRate >= 1 || canPlaySlow else {
            pause()
            errorMessage = "Slow playback unavailable."
            return
        }
        if !audioActive {
            guard !audioActivating else { return }
            audioActivating = true
            let token = UUID()
            audioRequest = token
            PlaybackAudioSession.setActive(true) { [weak self] errorCode in
                Task { @MainActor in
                    guard let self, self.audioRequest == token else { return }
                    self.audioActivating = false
                    if let errorCode {
                        self.pause()
                        self.errorMessage = "Audio unavailable (\(errorCode))."
                    } else {
                        self.audioActive = true
                        self.resumeIfNeeded()
                    }
                }
            }
            return
        }
        if player.rate != speed.effective { player.rate = speed.effective }
        UIApplication.shared.isIdleTimerDisabled = true
        trace("resume")
    }

    func setRate(_ rate: Float) {
        guard PlaybackPolicy.rates.contains(rate), rate >= 1 || canPlaySlow else { return }
        speed.select(rate)
        resumeIfNeeded()
    }

    func beginTemporaryDoubleRate() {
        speed.beginHold(isPlaying: wantsPlayback && isReady && !isSeeking && seekPreview == nil && player.timeControlStatus == .playing)
        if speed.isBoosting { resumeIfNeeded(); trace("hold began") }
    }

    func endTemporaryDoubleRate() {
        guard speed.isBoosting else { return }
        speed.endHold()
        resumeIfNeeded()
        trace("hold ended")
    }

    func skip(forward: Bool) {
        guard isReady, duration > 0, seekPreview == nil else { return }
        speed.endHold()
        // While a seek is in flight, accumulate from its latest requested target.
        // Reading AVPlayer's old currentTime here would discard rapid double taps.
        let origin = seekQueue.isBusy ? position : player.currentTime().seconds
        let target = PlaybackPolicy.skip(from: origin, forward: forward, duration: duration)
        commitSeek(target)
        showFeedback(SkipFeedback(forward: forward, origin: PlaybackPolicy.position(origin, duration: duration), target: target, duration: duration))
    }

    func setVoicePitch(_ value: Bool) {
        voicePitch = value
        player.currentItem?.audioTimePitchAlgorithm = value ? .timeDomain : .spectral
    }

    @discardableResult func beginScrubbing() -> Bool { beginPreview(.bar) }

    private func beginPreview(_ source: SeekPreview.Source) -> Bool {
        guard isReady, duration > 0, seekPreview == nil else { return false }
        if source == .horizontal && speed.isBoosting { return false }
        let origin = PlaybackPolicy.position(seekQueue.isBusy ? position : player.currentTime().seconds, duration: duration)
        clearFeedback()
        speed.endHold()
        seekPreview = SeekPreview(source: source, origin: origin, target: origin)
        player.pause()
        trace("preview begin \(source)")
        return true
    }

    func scrub(to seconds: Double) {
        guard var preview = seekPreview, preview.source == .bar else { return }
        preview.target = PlaybackPolicy.position(seconds, duration: duration)
        seekPreview = preview
    }

    func endScrubbing() { commitPreview(.bar) }
    func cancelScrubbing() { cancelPreview(.bar) }

    @discardableResult func beginHorizontalSeek() -> Bool { beginPreview(.horizontal) }
    func updateHorizontalSeek(translation: Double, width: Double) {
        guard var preview = seekPreview, preview.source == .horizontal else { return }
        preview.target = SeekInteractionPolicy.horizontalPosition(origin: preview.origin, translation: translation, width: width, duration: duration)
        seekPreview = preview
    }
    func endHorizontalSeek() { commitPreview(.horizontal) }
    func cancelHorizontalSeek() { cancelPreview(.horizontal) }

    private func commitPreview(_ source: SeekPreview.Source) {
        guard let preview = seekPreview, preview.source == source else { return }
        seekPreview = nil
        trace("preview commit \(source) target=\(preview.target)")
        commitSeek(preview.target)
    }
    private func cancelPreview(_ source: SeekPreview.Source) {
        guard let preview = seekPreview, preview.source == source else { return }
        seekPreview = nil
        position = seekQueue.isBusy ? preview.origin : PlaybackPolicy.position(player.currentTime().seconds, duration: duration)
        resumeIfNeeded()
    }
    private func commitSeek(_ seconds: Double) {
        position = PlaybackPolicy.position(seconds, duration: duration)
        keepsPlaybackAtSkippedEnd = wantsPlayback && position >= duration
        enqueueSeek(position, exact: true)
    }

    private func showFeedback(_ feedback: SkipFeedback) {
        feedbackTask?.cancel()
        skipFeedback = feedback
        feedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: SeekInteractionPolicy.feedbackDuration) } catch { return }
            guard !Task.isCancelled, self?.skipFeedback?.id == feedback.id else { return }
            self?.skipFeedback = nil
        }
    }
    private func clearFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        skipFeedback = nil
    }

    private func enqueueSeek(_ seconds: Double, exact: Bool, timescale: Int32 = 600) {
        guard isReady, duration > 0 else { return }
        let request = SeekRequest(seconds: PlaybackPolicy.position(seconds, duration: duration), exact: exact, timescale: timescale)
        player.pause()
        isSeeking = true
        if let next = seekQueue.enqueue(request) { performSeek(next) }
        else {
            // A newly committed position supersedes the in-flight destination.
            // Do not make it wait for decoding an obsolete frame. Cancellation
            // completes that request with finished=false; its completion then
            // starts the latest queued request, still with only one in flight.
            trace("new seek cancels superseded destination")
            player.currentItem?.cancelPendingSeeks()
        }
    }

    private func performSeek(_ request: SeekRequest) {
        let currentSession = session
        trace("seek start \(request.seconds), exact=\(request.exact)")
        let diagnostics = ProcessInfo.processInfo.arguments.contains("--playback-diagnostics")
        let tolerance = request.exact ? CMTime.zero : CMTime(seconds: 0.15, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: request.seconds, preferredTimescale: request.timescale), toleranceBefore: tolerance, toleranceAfter: tolerance) {
            @Sendable [weak self] finished in
            if diagnostics { print("Playback: tick=\(ProcessInfo.processInfo.systemUptime) seek callback received finished=\(finished)") }
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                if let next = self.seekQueue.finish() { self.performSeek(next) }
                else {
                    self.isSeeking = false
                    if self.seekPreview == nil { self.position = PlaybackPolicy.position(self.player.currentTime().seconds, duration: self.duration) }
                    if finished { self.resumeIfNeeded() }
                    else {
                        self.pause()
                        self.errorMessage = "Cannot seek. Please retry."
                    }
                    // A paused player may not emit another periodic callback after the seek.
                    self.refresh(ifSession: currentSession)
                    self.trace("seek completed=\(finished)")
                }
            }
        }
    }

    func beginFrameExtraction() -> FrameAsset? {
        guard isReady, !isSeeking, seekPreview == nil, let item = player.currentItem else { return nil }
        clearFeedback()
        pause()
        let entry = player.currentTime()
        let resources = PHAssetResource.assetResources(for: asset)
        let flags = FrameInputFlags(adjustmentData: resources.contains { $0.type == .adjustmentData },
                                    adjustmentBaseVideo: resources.contains { $0.type == .adjustmentBaseVideo },
                                    highFrameRate: asset.mediaSubtypes.contains(.videoHighFrameRate),
                                    timelapse: asset.mediaSubtypes.contains(.videoTimelapse), videoComposition: item.videoComposition != nil)
        let name = resources.first { $0.type == .video }?.originalFilename
        return FrameAsset(asset: item.asset, entry: entry, flags: flags,
                          fileStem: FrameFileName.stem(original: name, identifier: asset.localIdentifier))
    }

    func returnFromFrames(at time: CMTime) {
        pause()
        guard time.isNumeric else { return }
        // Preserve the measured time base (e.g. 30000 for 29.97 fps) on return.
        position = time.seconds
        enqueueSeek(time.seconds, exact: true, timescale: time.timescale)
    }

    func cancelInteractionForRotation() {
        gestureCancellationID += 1
        speed.endHold()
        cancelScrubbing()
        cancelHorizontalSeek()
        clearFeedback()
        // Rotation discards only uncommitted interaction state. An already
        // committed seek, the selected rate and playback intent stay intact.
        resumeIfNeeded()
    }

    func suspend() {
        clearFeedback()
        pause()
        if isLoading { cancelLoading() }
        deactivateAudio()
    }

    private func deactivateAudio() {
        audioRequest = UUID()
        if audioActive || audioActivating { PlaybackAudioSession.setActive(false) }
        audioActive = false
        audioActivating = false
    }

    func close() {
        clearFeedback()
        heldResult = nil
        isTestResultHeld = false
        session = UUID()
        requestGate.cancel()
        if let requestID { manager.cancelImageRequest(requestID) }
        requestID = nil
        seekPreview = nil
        seekQueue.cancel()
        player.currentItem?.cancelPendingSeeks()
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.forEach { $0.invalidate() }
        observations = []
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications = []
        player.replaceCurrentItem(with: nil)
        isReady = false
        isLoading = false
        isSeeking = false
        deactivateAudio()
    }

    var diagnosticText: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return """
        PhotoPlayer build \(build)
        Duration: \(PlaybackPolicy.clock(duration)) / Position: \(PlaybackPolicy.clock(position))
        Size: \(asset.pixelWidth)×\(asset.pixelHeight) / HDR: \(hdrDescription)
        Rate: selected \(selectedRate) / actual \(actualRate) / Slow support: \(canPlaySlow)
        State: \(stateText) / Photos progress: \(Int(progress * 100))%
        Pitch correction: \(voicePitch ? "Voice" : "Standard")
        Error: \(errorMessage ?? "No")
        """
    }
}
