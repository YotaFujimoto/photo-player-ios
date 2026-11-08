import SwiftUI
import AVFoundation
import Photos

struct PlayerScreen: View {
    let video: LibraryVideo
    let selectionTrace: SelectionTrace?
    let selectionOperation: Int?
    @StateObject private var model: PlaybackModel
    @State private var diagnostics: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(video: LibraryVideo, selectionDiagnostics: Bool = false, selectionTrace: SelectionTrace? = nil, selectionOperation: Int? = nil) {
        self.video = video
        self.selectionTrace = selectionTrace
        self.selectionOperation = selectionOperation
        _model = StateObject(wrappedValue: PlaybackModel(asset: video.asset))
        _diagnostics = State(initialValue: selectionDiagnostics)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    selectionTrace?.controlAction("player.close")
                    if let selectionOperation { selectionTrace?.closeRequested(selectionOperation) }
                    model.close(); dismiss()
                } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("closePlayer")
                .background {
                    if let selectionTrace {
                        ContactProbe(number: 0, trace: selectionTrace, control: "player.close").allowsHitTesting(false)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(diagnostics ? "Video \(video.diagnosticNumber)" : "Playback").font(.headline)
                        .accessibilityIdentifier("selectedVideo")
                        .accessibilityValue("\(model.asset.pixelWidth)x\(model.asset.pixelHeight)")
                    if diagnostics {
                        Text("\(Int(model.pictureSize.width))x\(Int(model.pictureSize.height))")
                            .font(.caption.monospacedDigit()).accessibilityIdentifier("loadedVideoSize")
                    }
                }
                Spacer()
                Button {
                    selectionTrace?.controlAction("player.diagnostics")
                    diagnostics.toggle()
                } label: {
                    Image(systemName: "info.circle").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                    .accessibilityLabel("Playback diagnostics")
                    .accessibilityIdentifier("playerDiagnostics")
                    .background {
                        if let selectionTrace {
                            ContactProbe(number: 0, trace: selectionTrace, control: "player.diagnostics").allowsHitTesting(false)
                        }
                    }
            }.padding(.horizontal)
            if diagnostics, let selectionTrace { SelectionTracePanel(trace: selectionTrace, location: "player") }
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    HStack(spacing: 0) {
                        picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { controls.padding() }.frame(width: min(280, geometry.size.width * 0.35))
                    }
                } else {
                    VStack(spacing: 0) {
                        picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if diagnostics {
                            ScrollView { controls.padding() }.frame(maxHeight: geometry.size.height * 0.5)
                        } else { controls.padding() }
                    }
                }
            }
        }
        .onAppear {
            if let selectionOperation { selectionTrace?.appear(selectionOperation) }
            model.onLoadEvent = { [weak selectionTrace, selectionOperation] event in
                if let selectionOperation { selectionTrace?.loadEvent(event, operation: selectionOperation) }
            }
            model.load()
        }
        .onDisappear {
            model.close()
            if let selectionOperation { selectionTrace?.disappear(selectionOperation) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.suspend() } }
    }

    private var picture: some View {
        ZStack {
            PlayerSurface(model: model)
            if model.isTemporaryDoubleRate {
                Text("2×").font(.headline.monospacedDigit()).padding(10)
                    .background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
                    .accessibilityIdentifier("temporaryRate")
            }
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView(value: model.hasDownloadProgress ? model.progress : nil)
                    Text(model.hasDownloadProgress ? "Downloading \(Int(model.progress * 100))%" : "Loading…")
                        .accessibilityIdentifier("videoLoading")
                    if ProcessInfo.processInfo.arguments.contains("--hold-player-result") {
                        Button("Release test result") { model.releaseTestResult() }
                            .disabled(!model.isTestResultHeld)
                            .accessibilityIdentifier("releasePlayerResult")
                    }
                    Button("Cancel") { model.cancelLoading() }.accessibilityIdentifier("cancelDownload")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            } else if let error = model.errorMessage {
                VStack(spacing: 12) {
                    Text(error).font(.callout)
                    Button("Retry") { model.load() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("retryVideo")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            } else if !model.isReady { ProgressView().tint(.white) }
        }.background(.black)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Text(PlaybackPolicy.clock(model.position)).accessibilityIdentifier("playbackPosition")
                Spacer()
                Text(PlaybackPolicy.clock(model.duration)).accessibilityIdentifier("playbackDuration")
            }.font(.caption.monospacedDigit())
            Slider(value: Binding(get: { model.position }, set: { model.scrub(to: $0) }),
                   in: 0...max(model.duration, 1), onEditingChanged: { editing in
                if editing { model.beginScrubbing() } else { model.endScrubbing() }
            })
            .disabled(!model.isReady || model.duration <= 0)
            .accessibilityLabel("Playback position").accessibilityIdentifier("seekSlider")

            HStack {
                Button { model.togglePlayback() } label: {
                    Label(model.wantsPlayback ? "Pause" : "Play", systemImage: model.wantsPlayback ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!model.isReady)
                    .accessibilityIdentifier("playPause").accessibilityValue(model.stateText)
                Spacer()
                Menu {
                    ForEach(PlaybackPolicy.rates, id: \.self) { rate in
                        Button(String(format: "%g×", rate)) { model.setRate(rate) }
                            .disabled(rate < 1 && !model.canPlaySlow)
                    }
                } label: {
                    Text(String(format: "%g×", model.selectedRate)).frame(minWidth: 44, minHeight: 44)
                }.disabled(!model.isReady).accessibilityIdentifier("rateMenu")
                    .accessibilityLabel("Playback speed").accessibilityValue(String(format: "%g×", model.selectedRate))
            }
            if diagnostics || model.stateText == "Buffering…" {
                Text(model.stateText).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("playerState")
            }
            if model.isReady && !model.canPlaySlow {
                Text("Slow playback unavailable.").font(.caption)
            }
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
