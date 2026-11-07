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
    @Published private(set) var selectedRate: Float = 1
    @Published private(set) var actualRate: Float = 0
    @Published private(set) var wantsPlayback = false
    @Published private(set) var canPlaySlow = false
    @Published private(set) var isSeeking = false
    @Published private(set) var stateText = "準備中"
    @Published private(set) var pictureSize = CGSize.zero
    @Published private(set) var hdrDescription = "確認中"
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
    private var scrubbing = false
    private var scrubTask: Task<Void, Never>?
    private var audioActive = false
    private var audioActivating = false
    private var audioRequest = UUID()

    init(asset: PHAsset) { self.asset = asset }

    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PlaybackModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func trace(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("--playback-diagnostics") else { return }
        print("Playback: \(event), time=\(position), selected=\(selectedRate), actual=\(player.rate), state=\(stateText)")
    }

    func load() {
        close()
        errorMessage = nil
        duration = asset.duration
        position = 0
        progress = 0
        hasDownloadProgress = false
        hdrDescription = "確認中"
        selectedRate = 1
        stateText = "準備中"
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
                if let errorCode { self.failDownload("動画の取得に失敗しました（\(errorCode)）。接続を確認して再試行してください。") }
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
            errorMessage = "取得をキャンセルしました。"
            onLoadEvent?(.failed)
        } else if let item = result.item {
            progress = 1
            onLoadEvent?(.received)
            install(item)
        } else {
            wantsPlayback = false
            errorMessage = "動画を取得できません（\(result.errorCode ?? "利用不可")）。接続・写真のアクセス権を確認して再試行してください。"
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

    func cancelLoading() { failDownload("取得をキャンセルしました。") }

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
        stateText = "取得停止"
    }

    private func install(_ item: AVPlayerItem) {
        let currentSession = session
        item.asset.loadTracks(withMediaCharacteristic: .containsHDRVideo) { @Sendable [weak self] tracks, _ in
            let description = tracks.map { $0.isEmpty ? "なし" : "あり" } ?? "不明"
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
                self.pause()
                self.position = self.duration
                self.stateText = "終了"
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) {
            [weak self] note in
            let code = PlaybackPolicy.errorCode(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                self.pause()
                self.errorMessage = "再生に失敗しました（\(code)）。"
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
            errorMessage = "再生を準備できません（\(PlaybackPolicy.errorCode(item.error))）。"
            stateText = "エラー"
            return
        }
        let firstReady = !isReady && item.status == .readyToPlay
        if firstReady { onLoadEvent?(.ready) }
        assign(\.isReady, item.status == .readyToPlay)
        assign(\.canPlaySlow, isReady && item.canPlaySlowForward)
        let seconds = item.duration.seconds
        if seconds.isFinite && seconds > 0 { assign(\.duration, seconds) }
        assign(\.pictureSize, item.presentationSize)
        if !scrubbing && !seekQueue.isBusy { assign(\.position, PlaybackPolicy.position(player.currentTime().seconds, duration: duration)) }
        assign(\.bufferedUntil, item.loadedTimeRanges.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds }
            .filter(\.isFinite).max() ?? 0)
        assign(\.actualRate, player.rate)
        let newState: String
        if !isReady { newState = "準備中" }
        else if isSeeking { newState = "移動中" }
        else {
            switch player.timeControlStatus {
            case .playing: newState = "再生中"
            case .waitingToPlayAtSpecifiedRate: newState = "読み込み待ち"
            case .paused: newState = position >= duration && duration > 0 ? "終了" : "一時停止"
            @unknown default: newState = "待機中"
            }
        }
        assign(\.stateText, newState)
        if firstReady && wantsPlayback { resumeIfNeeded() }
    }

    func togglePlayback() {
        if wantsPlayback { pause() }
        else {
            wantsPlayback = true
            if duration > 0 && position >= duration - 0.1 { enqueueSeek(0, exact: true) }
            else { resumeIfNeeded() }
        }
    }

    func pause() {
        assign(\.wantsPlayback, false)
        if player.timeControlStatus != .paused || player.rate != 0 { player.pause() }
        assign(\.actualRate, 0)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func resumeIfNeeded() {
        guard wantsPlayback, isReady, !scrubbing, !seekQueue.isBusy else { return }
        guard selectedRate >= 1 || canPlaySlow else {
            pause()
            errorMessage = "この動画は低速再生に対応していません。"
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
                        self.errorMessage = "音声を準備できません（\(errorCode)）。"
                    } else {
                        self.audioActive = true
                        self.resumeIfNeeded()
                    }
                }
            }
            return
        }
        if player.rate != selectedRate { player.rate = selectedRate }
        UIApplication.shared.isIdleTimerDisabled = true
        trace("resume")
    }

    func setRate(_ rate: Float) {
        guard PlaybackPolicy.rates.contains(rate), rate >= 1 || canPlaySlow else { return }
        selectedRate = rate
        resumeIfNeeded()
    }

    func setVoicePitch(_ value: Bool) {
        voicePitch = value
        player.currentItem?.audioTimePitchAlgorithm = value ? .timeDomain : .spectral
    }

    func beginScrubbing() {
        scrubbing = true
        player.pause()
    }

    func scrub(to seconds: Double) {
        position = PlaybackPolicy.position(seconds, duration: duration)
        guard scrubbing else { return }
        if scrubTask == nil {
            scrubTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.scrubTask = nil
                self.enqueueSeek(self.position, exact: false)
            }
        }
    }

    func endScrubbing() {
        scrubTask?.cancel()
        scrubTask = nil
        scrubbing = false
        enqueueSeek(position, exact: true)
    }

    private func enqueueSeek(_ seconds: Double, exact: Bool) {
        guard isReady, duration > 0 else { return }
        let request = SeekRequest(seconds: PlaybackPolicy.position(seconds, duration: duration), exact: exact)
        player.pause()
        isSeeking = true
        if let next = seekQueue.enqueue(request) { performSeek(next) }
    }

    private func performSeek(_ request: SeekRequest) {
        let currentSession = session
        trace("seek start \(request.seconds), exact=\(request.exact)")
        let tolerance = request.exact ? CMTime.zero : CMTime(seconds: 0.15, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: request.seconds, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) {
            @Sendable [weak self] finished in Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                if let next = self.seekQueue.finish() { self.performSeek(next) }
                else {
                    self.isSeeking = false
                    if !self.scrubbing { self.position = PlaybackPolicy.position(self.player.currentTime().seconds, duration: self.duration) }
                    if finished { self.resumeIfNeeded() }
                    else {
                        self.pause()
                        self.errorMessage = "指定位置へ移動できませんでした。再試行してください。"
                    }
                    // A paused player may not emit another periodic callback after the seek.
                    self.refresh(ifSession: currentSession)
                    self.trace("seek completed=\(finished)")
                }
            }
        }
    }

    func suspend() {
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
        heldResult = nil
        isTestResultHeld = false
        session = UUID()
        requestGate.cancel()
        if let requestID { manager.cancelImageRequest(requestID) }
        requestID = nil
        scrubTask?.cancel()
        scrubTask = nil
        scrubbing = false
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
        長さ: \(PlaybackPolicy.clock(duration)) / 位置: \(PlaybackPolicy.clock(position))
        解像度: \(asset.pixelWidth)×\(asset.pixelHeight) / HDR: \(hdrDescription)
        速度: 選択 \(selectedRate) / 実際 \(actualRate) / 低速対応: \(canPlaySlow)
        状態: \(stateText) / Photos取得進捗: \(Int(progress * 100))%
        音程補正: \(voicePitch ? "音声向け" : "標準")
        エラー: \(errorMessage ?? "なし")
        """
    }
}
