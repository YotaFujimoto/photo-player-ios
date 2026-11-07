import SwiftUI
import AVFoundation
import Photos

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) { uiView.playerLayer.player = player }
    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) { uiView.playerLayer.player = nil }
}

struct PlayerScreen: View {
    let video: LibraryVideo
    @StateObject private var model: PlaybackModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(video: LibraryVideo) {
        self.video = video
        _model = StateObject(wrappedValue: PlaybackModel(asset: video.asset))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("閉じる", systemImage: "xmark") { model.close(); dismiss() }
                    .accessibilityIdentifier("closePlayer")
                Spacer()
                Text("再生").font(.headline)
                Spacer()
            }.padding()
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    HStack(spacing: 0) {
                        picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { controls.padding() }.frame(width: min(320, geometry.size.width * 0.42))
                    }
                } else {
                    VStack(spacing: 0) {
                        picture.frame(height: min(geometry.size.width * 9 / 16, geometry.size.height * 0.55))
                        ScrollView { controls.padding() }
                    }
                }
            }
        }
        .onAppear { model.load() }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.suspend() } }
    }

    private var picture: some View {
        ZStack {
            PlayerSurface(player: model.player).accessibilityIdentifier("videoSurface")
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView(value: model.cloudDownload ? model.progress : nil)
                    Text(model.cloudDownload ? "iCloudから取得中 \(Int(model.progress * 100))%" : "動画を準備中")
                    Button("取得をキャンセル") { model.cancelLoading() }
                        .accessibilityIdentifier("cancelDownload")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            } else if let error = model.errorMessage {
                VStack(spacing: 12) {
                    Text(error).font(.callout)
                    Button("再試行") { model.load() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("retryVideo")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            } else if !model.isReady { ProgressView().tint(.white) }
        }.background(.black)
    }

    private var controls: some View {
        VStack(spacing: 16) {
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
            .accessibilityLabel("再生位置").accessibilityIdentifier("seekSlider")

            HStack {
                Button { model.togglePlayback() } label: {
                    Label(model.wantsPlayback ? "一時停止" : "再生", systemImage: model.wantsPlayback ? "pause.fill" : "play.fill")
                        .frame(minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!model.isReady)
                    .accessibilityIdentifier("playPause")
                Spacer()
                Menu {
                    ForEach(PlaybackPolicy.rates, id: \.self) { rate in
                        Button(String(format: "%g×", rate)) { model.setRate(rate) }
                            .disabled(rate < 1 && !model.canPlaySlow)
                    }
                } label: {
                    Text(String(format: "速度 %g×", model.selectedRate)).frame(minHeight: 44)
                }.disabled(!model.isReady).accessibilityIdentifier("rateMenu")
            }
            Text(model.stateText).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("playerState")
            if model.isReady && !model.canPlaySlow {
                Text("この素材は低速再生に対応していません。").font(.caption)
            }

            DisclosureGroup("再生情報") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(video.asset.pixelWidth) × \(video.asset.pixelHeight) / HDR: \(model.hdrDescription)")
                    Text(String(format: "実再生速度 %.2f×", model.actualRate)).accessibilityIdentifier("actualRate")
                    Text("取得: \(model.cloudDownload ? "iCloud" : "Photos") / バッファ終端: \(PlaybackPolicy.clock(model.bufferedUntil))")
                    Toggle("音声向けの音程補正", isOn: Binding(get: { model.voicePitch }, set: { model.setVoicePitch($0) }))
                    Text("オフは標準。低速時の音質を比較できます。動画名や識別子は診断に含めません。")
                        .foregroundStyle(.secondary)
                    Button("再生情報をコピー") { UIPasteboard.general.string = model.diagnosticText }
                }.font(.caption).padding(.top, 8)
            }.accessibilityIdentifier("playbackDetails")
        }
    }
}
