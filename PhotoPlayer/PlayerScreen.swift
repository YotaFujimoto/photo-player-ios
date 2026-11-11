import SwiftUI
import AVFoundation
import Photos

struct PlayerScreen: View {
    let video: LibraryVideo
    let selectionTrace: SelectionTrace?
    let selectionOperation: Int?
    @StateObject private var model: PlaybackModel
    @StateObject private var chrome = PlaybackChrome()
    @State private var diagnostics: Bool
    @State private var rateMenuVisible = false
    @State private var extraction: FrameExtractionModel?
    @State private var saveNotice: String?
    @State private var lastDeviceOrientation = UIDeviceOrientation.unknown
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(video: LibraryVideo, selectionDiagnostics: Bool = false, selectionTrace: SelectionTrace? = nil, selectionOperation: Int? = nil) {
        self.video = video
        self.selectionTrace = selectionTrace
        self.selectionOperation = selectionOperation
        _model = StateObject(wrappedValue: PlaybackModel(asset: video.asset))
        _diagnostics = State(initialValue: selectionDiagnostics || ProcessInfo.processInfo.arguments.contains("--player-detail-mode"))
    }

    var body: some View {
        GeometryReader { geometry in
            let fullscreen = geometry.size.width > geometry.size.height
            if let extraction {
                FrameExtractionScreen(model: extraction) { count in
                    let time = extraction.displayedTime ?? extraction.entryTime
                    extraction.close()
                    self.extraction = nil
                    lastDeviceOrientation = UIDevice.current.orientation
                    chrome.setActive(scenePhase == .active)
                    model.returnFromFrames(at: time)
                    if count > 0 { saveNotice = "Saved \(count) \(count == 1 ? "photo" : "photos")." }
                }
            } else {
            ZStack {
                picture(fullscreen: true).ignoresSafeArea()
                if chrome.isVisible {
                    Button { chrome.activity(); model.togglePlayback() } label: {
                        Image(systemName: model.showsPauseControl ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .semibold)).frame(width: 80, height: 80).mediaGlass()
                    }.disabled(!model.isReady).accessibilityLabel(model.showsPauseControl ? "Pause" : "Play")
                        .accessibilityIdentifier("playPause").accessibilityValue(model.stateText)
                        .buttonStyle(TrackedPlayerButtonStyle(onPress: { chrome.block(.button("playPause"), active: $0) }))
                    VStack(spacing: 0) {
                        header
                        if diagnostics, let selectionTrace {
                            ScrollView { SelectionTracePanel(trace: selectionTrace, location: "player") }
                                .frame(maxHeight: min(90, geometry.size.height * 0.20))
                        }
                        Spacer(minLength: 0)
                        if diagnostics {
                            ScrollView { controls(fullscreen: true) }.frame(maxHeight: min(210, geometry.size.height * 0.4))
                        } else { controls(fullscreen: true) }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                        .transition(.opacity)
                }
            }.foregroundStyle(.white).tint(.white).background(.black)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("selectedVideo")
                .accessibilityLabel(diagnostics ? "Video \(video.diagnosticNumber)" : "Playback")
                .accessibilityValue("\(model.asset.pixelWidth)x\(model.asset.pixelHeight)")
                .animation(.easeOut(duration: 0.18), value: chrome.isVisible)
            .statusBarHidden(fullscreen)
            .onAppear { configureLayout(fullscreen: fullscreen) }
            .onChange(of: geometry.size) { _, _ in configureLayout(fullscreen: fullscreen) }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let orientation = UIDevice.current.orientation
                guard [.portrait, .landscapeLeft, .landscapeRight].contains(orientation),
                      orientation != lastDeviceOrientation else { return }
                lastDeviceOrientation = orientation
                // A 180-degree landscape turn does not change geometry.size.
                configureLayout(fullscreen: fullscreen)
            }
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            lastDeviceOrientation = UIDevice.current.orientation
            chrome.setActive(scenePhase == .active)
            if let selectionOperation { selectionTrace?.appear(selectionOperation) }
            model.onLoadEvent = { [weak selectionTrace, selectionOperation] event in
                if let selectionOperation { selectionTrace?.loadEvent(event, operation: selectionOperation) }
            }
            model.load()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            chrome.setActive(false); rateMenuVisible = false
            extraction?.close()
            model.close()
            if let selectionOperation { selectionTrace?.disappear(selectionOperation) }
        }
        .onChange(of: model.showsPauseControl) { _, playing in chrome.playback(playing: playing) }
        .onChange(of: model.isSeeking) { _, seeking in chrome.block(.seeking, active: seeking) }
        .onChange(of: model.isReady) { _, _ in refreshAvailability() }
        .onChange(of: model.errorMessage) { _, _ in refreshAvailability() }
        .onChange(of: diagnostics) { _, value in chrome.block(.diagnostics, active: value) }
        .onChange(of: scenePhase) { _, phase in
            chrome.setActive(phase == .active)
            rateMenuVisible = false
            if phase != .active { model.suspend() }
            else { refreshChrome() }
        }
    }

    private func configureLayout(fullscreen: Bool) {
        rateMenuVisible = false
        model.cancelInteractionForRotation()
        chrome.layout(fullscreen: true)
        refreshChrome()
    }
    private func refreshChrome() {
        chrome.playback(playing: model.showsPauseControl)
        chrome.block(.diagnostics, active: diagnostics)
        chrome.block(.seeking, active: model.isSeeking)
        refreshAvailability()
    }
    private func refreshAvailability() {
        chrome.block(.unavailable, active: !model.isReady || model.errorMessage != nil)
    }

    private var header: some View {
        HStack {
            Button {
                selectionTrace?.controlAction("player.close")
                if let selectionOperation { selectionTrace?.closeRequested(selectionOperation) }
                chrome.setActive(false); rateMenuVisible = false
                model.close(); dismiss()
            } label: {
                Image(systemName: "xmark").frame(width: 48, height: 48).contentShape(Circle()).mediaGlass()
            }
            .accessibilityLabel("Close").accessibilityIdentifier("closePlayer")
            .buttonStyle(TrackedPlayerButtonStyle(onPress: { chrome.block(.button("closePlayer"), active: $0) }))
            .background {
                if let selectionTrace { ContactProbe(number: 0, trace: selectionTrace, control: "player.close").allowsHitTesting(false) }
            }
            Spacer()
            if diagnostics { VStack(spacing: 2) {
                Text("Video \(video.diagnosticNumber)").font(.headline)
                    .accessibilityIdentifier("playerVideoTitle")
                if diagnostics {
                    Text("\(Int(model.pictureSize.width))x\(Int(model.pictureSize.height))")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("loadedVideoSize")
                }
            }
            }
            Spacer()
            Button {
                guard let input = model.beginFrameExtraction() else { return }
                rateMenuVisible = false; saveNotice = nil
                chrome.setActive(false)
                let frameModel = FrameExtractionModel(source: FrameSource(input: input), fileStem: input.fileStem, entryTime: input.entry)
                if let selectionTrace {
                    let operation = selectionTrace.beginFrameOperation(video: video.diagnosticNumber)
                    frameModel.onDiagnostic = { [weak selectionTrace] report in selectionTrace?.recordFrameOperation(operation, text: report) }
                }
                extraction = frameModel
            } label: {
                Image(systemName: "photo.badge.plus").frame(width: 48, height: 48).contentShape(Circle()).mediaGlass()
            }
            .accessibilityLabel("Save frames").accessibilityIdentifier("extractFrames")
            .disabled(!model.isReady || model.isSeeking || model.seekPreview != nil)
            .buttonStyle(TrackedPlayerButtonStyle(onPress: { chrome.block(.button("extractFrames"), active: $0) }))
        }
    }

    private func picture(fullscreen: Bool) -> some View {
        PlayerSurface(model: model, fullscreen: fullscreen, onSingleTap: chrome.singleTap,
                      onActivity: chrome.activity, onInteractionChanged: { chrome.block(.videoGesture, active: $0) })
        .overlay { SeekFeedbackOverlay(preview: model.seekPreview, skip: model.skipFeedback, pictureSize: model.pictureSize) }
        .overlay(alignment: .top) {
            if let saveNotice {
                Text(saveNotice).font(.callout).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 8).padding(.top, fullscreen ? 60 : 8)
                    .accessibilityIdentifier("frameSaveSuccess").allowsHitTesting(false)
                    .task(id: saveNotice) {
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        self.saveNotice = nil
                    }
            }
        }
        .overlay {
            if model.isTemporaryDoubleRate {
                Text("2×").font(.headline.monospacedDigit()).padding(10)
                    .background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
                    .accessibilityIdentifier("temporaryRate")
            }
        }
        .overlay {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView(value: model.hasDownloadProgress ? model.progress : nil)
                    Text(model.hasDownloadProgress ? "Downloading \(Int(model.progress * 100))%" : "Loading…")
                        .accessibilityIdentifier("videoLoading")
                    if ProcessInfo.processInfo.arguments.contains("--hold-player-result") {
                        Button("Release test result") { model.releaseTestResult() }
                            .disabled(!model.isTestResultHeld).accessibilityIdentifier("releasePlayerResult")
                    }
                    Button("Cancel") { model.cancelLoading() }.accessibilityIdentifier("cancelDownload")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            } else if let error = model.errorMessage {
                VStack(spacing: 12) {
                    Text(error).font(.callout)
                    Button("Retry") { model.load() }.buttonStyle(.borderedProminent).accessibilityIdentifier("retryVideo")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            } else if !model.isReady { ProgressView().tint(.white) }
        }
        .overlay(alignment: .bottom) {
            if model.isReady && !model.canPlaySlow {
                Text("Slow playback unavailable.").font(.caption).padding(8)
                    .background(.regularMaterial, in: Capsule()).padding(8).allowsHitTesting(false)
            }
        }
        .background(.black)
    }

    private func controls(fullscreen: Bool) -> some View {
        VStack(spacing: 12) {
            PlaybackTransportControls(state: PlaybackTransportState(
                position: model.displayedPosition, duration: model.duration, isReady: model.isReady,
                canPlaySlow: model.canPlaySlow, showsPause: model.showsPauseControl,
                selectedRate: model.selectedRate, stateText: model.stateText,
                cancellationID: model.gestureCancellationID), diagnostics: diagnostics, fullscreen: fullscreen,
                ratePresentation: Binding(get: { rateMenuVisible }, set: {
                    rateMenuVisible = $0; chrome.block(.speedMenu, active: $0)
                }),
                actions: PlaybackTransportActions(begin: {
                    let accepted = model.beginScrubbing()
                    if accepted { chrome.block(.bar, active: true) }
                    return accepted
                }, change: model.scrub, commit: {
                    model.endScrubbing(); chrome.block(.bar, active: false)
                }, cancel: {
                    model.cancelScrubbing(); chrome.block(.bar, active: false)
                }, togglePlayback: {
                    chrome.activity(); model.togglePlayback()
                }, setRate: {
                    chrome.activity(); model.setRate($0)
                }, pressing: { chrome.block(.button($0), active: $1) }))
            if diagnostics {
                DisclosureGroup("Playback details") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(video.asset.pixelWidth) × \(video.asset.pixelHeight) / HDR: \(model.hdrDescription)")
                        Text(String(format: "Actual rate %.2f×", model.actualRate)).accessibilityIdentifier("actualRate")
                        Text("Photos: \(Int(model.progress * 100))% / Buffered: \(PlaybackPolicy.clock(model.bufferedUntil))")
                        Toggle("Voice pitch correction", isOn: Binding(get: { model.voicePitch }, set: { model.setVoicePitch($0) }))
                        Text("Off uses the standard pitch correction. Diagnostics omit video names and library identifiers.")
                            .foregroundStyle(.secondary)
                        Button("Copy playback details") { UIPasteboard.general.string = model.diagnosticText }
                    }.font(.caption).padding(.top, 8)
                }
            }
        }
    }
}
