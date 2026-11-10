import SwiftUI

final class FramePreviewView: UIImageView {
    var onStep: ((Bool) -> Void)?
    var onBegin: (() -> Bool)?
    var onMove: ((Double, Double) -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    private let tap = UITapGestureRecognizer()
    private let swipe = HorizontalSeekGestureRecognizer()
    private var accepted = false
    private var lastSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black; contentMode = .scaleAspectFit; isUserInteractionEnabled = true
        accessibilityIdentifier = "framePreview"; isAccessibilityElement = true; accessibilityLabel = "Frame preview"
        tap.numberOfTapsRequired = 2; tap.addTarget(self, action: #selector(stepped(_:)))
        swipe.addTarget(self, action: #selector(moved(_:)))
        tap.require(toFail: swipe)
        addGestureRecognizer(tap); addGestureRecognizer(swipe)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func stepped(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { onStep?(recognizer.location(in: self).x >= bounds.midX) }
    }
    @objc private func moved(_ recognizer: HorizontalSeekGestureRecognizer) {
        switch recognizer.state {
        case .began:
            accepted = onBegin?() == true
            if accepted { onMove?(Double(recognizer.translation.x), Double(bounds.width)) }
        case .changed:
            if accepted { onMove?(Double(recognizer.translation.x), Double(bounds.width)) }
        case .ended:
            if accepted {
                onMove?(Double(recognizer.translation.x), Double(bounds.width))
                accepted = false; onEnd?()
            }
        case .cancelled, .failed:
            if accepted { accepted = false; onCancel?() }
        default: break
        }
    }
    func cancelFrameGesture() {
        if accepted { accepted = false; onCancel?() }
        swipe.isEnabled = false; swipe.isEnabled = true
        tap.isEnabled = false; tap.isEnabled = true
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { cancelFrameGesture(); lastSize = bounds.size }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelFrameGesture() } }
}

struct FramePreview: UIViewRepresentable {
    @ObservedObject var model: FrameExtractionModel
    func makeUIView(context: Context) -> FramePreviewView { FramePreviewView(frame: .zero) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FramePreviewView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
    func updateUIView(_ view: FramePreviewView, context: Context) {
        view.onStep = model.step; view.onBegin = model.beginInteraction; view.onMove = model.swipe
        view.onEnd = model.finishInteraction; view.onCancel = model.cancelInteraction
        if view.image?.cgImage !== model.preview { view.image = model.preview.map { UIImage(cgImage: $0) } }
        view.isUserInteractionEnabled = model.phase == .ready
        view.accessibilityValue = model.isPreviewing ? "Loading frame" : "Frame \(model.selection?.position ?? 0)"
    }
    static func dismantleUIView(_ view: FramePreviewView, coordinator: ()) {
        view.cancelFrameGesture()
        view.onStep = nil; view.onBegin = nil; view.onMove = nil; view.onEnd = nil; view.onCancel = nil
    }
}

struct FrameExtractionScreen: View {
    @ObservedObject var model: FrameExtractionModel
    let onClose: (Int) -> Void
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                FramePreview(model: model).ignoresSafeArea()
                VStack {
                    ZStack {
                        Text(model.selection?.summary ?? "Frames")
                            .font(.subheadline.monospacedDigit()).accessibilityIdentifier("frameSummary")
                        HStack {
                            Button { if model.canClose { onClose(0) } } label: {
                                Image(systemName: "xmark").frame(width: 44, height: 44)
                            }.accessibilityLabel("Cancel").accessibilityIdentifier("cancelFrames").disabled(!model.canClose)
                            Spacer()
                            Button { model.save() } label: {
                                Image(systemName: "checkmark").frame(width: 44, height: 44)
                            }.accessibilityLabel("Done").accessibilityIdentifier("saveFrames").disabled(!model.canSave)
                        }
                    }.padding(.horizontal, 8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        HStack {
                            Text(model.selection.map { PlaybackPolicy.clock($0.times[0].seconds) } ?? "0:00")
                            Spacer()
                            Text(model.displayedTime.map { String(format: "%.3f s", $0.seconds) } ?? "—")
                                .accessibilityIdentifier("framePosition")
                            Spacer()
                            Text(model.selection.map { PlaybackPolicy.clock($0.times.last!.seconds) } ?? "0:00")
                        }.font(.caption.monospacedDigit()).padding(.horizontal, 10)
                        FrameTimeline(model: model).frame(height: 44)
                        HStack {
                            Button("Set Start") { model.setStart() }
                                .disabled(!model.canSetEndpoints || model.selection?.canSetStart != true)
                                .accessibilityIdentifier("setFrameStart")
                            Spacer()
                            Button("Set End") { model.setEnd() }
                                .disabled(!model.canSetEndpoints || model.selection?.canSetEnd != true)
                                .accessibilityIdentifier("setFrameEnd")
                        }.buttonStyle(FrameEndpointStyle()).font(.caption)
                    }.padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }.padding(12)
                if model.phase == .loading || model.isPreviewing || model.phase == .preparing || model.phase == .saving {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(model.phase == .loading || model.isPreviewing ? "Loading frame…" : model.progress)
                            .font(.caption).accessibilityIdentifier("frameProgress")
                    }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)
                } else if let error = model.error {
                    VStack(spacing: 8) {
                        Text(error).font(.callout).multilineTextAlignment(.center).accessibilityIdentifier("frameError")
                        if model.phase == .unavailable { Button("Retry") { model.retryPreview() } }
                    }.padding().frame(maxWidth: 300).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }.background(.black).statusBarHidden(geometry.size.width > geometry.size.height)
                .onChange(of: geometry.size) { _, _ in model.cancelInteraction() }
        }
        .onAppear { model.prepare() }
        .onChange(of: model.savedCount) { _, count in if count > 0 { onClose(count) } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.backgrounded() } }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            model.cancelInteraction()
        }
    }
}

private struct FrameEndpointStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 90, minHeight: 44)
            .contentShape(Rectangle()).opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.5 : 1)
    }
}
