import SwiftUI

final class FramePreviewView: UIImageView, UIGestureRecognizerDelegate {
    var onToggleCrop: (() -> Void)?
    var onCropBegin: ((CGPoint, CGRect) -> Bool)?
    var onCropMove: ((CGPoint) -> Void)?
    var onCropEnd: (() -> Void)?
    var crop = FrameCrop.full { didSet { updateGuides() } }
    var cropping = false { didSet { if oldValue != cropping { cancelFrameGesture(); swipe.isEnabled = !cropping; cropPan.isEnabled = cropping; updateGuides() } } }
    var cancellationID = 0
    private let single = UITapGestureRecognizer()
    private let cropPan = CropGestureRecognizer()
    private let guides = CAShapeLayer()
    private let thirds = CAShapeLayer()
    var videoRect: CGRect { VideoGeometry.fitted(image?.size ?? .zero, in: bounds) }
    override var accessibilityValue: String? {
        get {
            guard ProcessInfo.processInfo.arguments.contains("--verify-crop-edges") else { return super.accessibilityValue }
            let r = crop.rect
            return (super.accessibilityValue ?? "") + String(format: "; crop=%.4f,%.4f,%.4f,%.4f; edges=%lu", r.minX,r.minY,r.width,r.height,CropEdgePolicy.resolvedEdges(window:window).rawValue)
        }
        set { super.accessibilityValue = newValue }
    }
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
        tap.require(toFail: swipe); tap.require(toFail: cropPan)
        single.addTarget(self, action: #selector(toggled(_:)))
        single.require(toFail: tap); single.require(toFail: swipe); single.require(toFail: cropPan)
        cropPan.addTarget(self, action: #selector(cropped(_:))); cropPan.isEnabled = false
        for recognizer in [single, tap, swipe, cropPan] { recognizer.delegate = self; addGestureRecognizer(recognizer) }
        guides.fillColor = UIColor.clear.cgColor; guides.strokeColor = UIColor.white.cgColor
        guides.shadowColor = UIColor.black.cgColor; guides.shadowOpacity = 0.8; guides.shadowRadius = 1
        thirds.fillColor = UIColor.clear.cgColor; thirds.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor; thirds.lineWidth = 0.5
        layer.addSublayer(guides); layer.addSublayer(thirds)
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Enter or leave crop adjustment", target: self, selector: #selector(accessibleCrop)),
            UIAccessibilityCustomAction(name: "Previous frame", target: self, selector: #selector(previousFrame)),
            UIAccessibilityCustomAction(name: "Next frame", target: self, selector: #selector(nextFrame))
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Touch slop is permitted at the real edge. Black bars are not crop coordinates.
        videoRect.insetBy(dx: -22, dy: -22).contains(touch.location(in: self))
    }
    @objc private func accessibleCrop() -> Bool { onToggleCrop?(); return true }
    @objc private func previousFrame() -> Bool { onStep?(false); return true }
    @objc private func nextFrame() -> Bool { onStep?(true); return true }
    @objc private func toggled(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { onToggleCrop?() }
    }
    @objc private func cropped(_ recognizer: CropGestureRecognizer) {
        switch recognizer.state {
        case .began:
            accepted = onCropBegin?(recognizer.origin, videoRect) == true
            if accepted { onCropMove?(recognizer.translation) }
        case .changed: if accepted { onCropMove?(recognizer.translation) }
        case .ended:
            if accepted { onCropMove?(recognizer.translation); accepted = false; onCropEnd?() }
        case .cancelled, .failed:
            if accepted { accepted = false; onCancel?() }
        default: break
        }
    }
    func updateGuides() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let rect = crop.displayed(in: videoRect)
        guides.path = UIBezierPath(rect: rect).cgPath
        guides.lineWidth = cropping ? 1.5 : 0.75
        guides.isHidden = image == nil || (!cropping && crop.isFull)
        let path = UIBezierPath()
        if cropping {
            for ratio in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                path.move(to: CGPoint(x: rect.minX + rect.width * ratio, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * ratio, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * ratio))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * ratio))
            }
        }
        thirds.path = path.cgPath
        CATransaction.commit()
    }
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
        swipe.isEnabled = false; swipe.isEnabled = !cropping
        cropPan.isEnabled = false; cropPan.isEnabled = cropping
        single.isEnabled = false; single.isEnabled = true
        tap.isEnabled = false; tap.isEnabled = true
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { cancelFrameGesture(); lastSize = bounds.size }
        updateGuides()
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
        view.onToggleCrop = model.toggleCrop; view.onCropBegin = model.beginCrop
        view.onCropMove = model.moveCrop; view.onCropEnd = model.finishCrop
        view.cropping = model.isCropping; view.crop = model.crop
        if view.cancellationID != model.gestureCancellationID { view.cancellationID = model.gestureCancellationID; view.cancelFrameGesture() }
        if view.image?.cgImage !== model.preview { view.image = model.preview.map { UIImage(cgImage: $0) } }
        view.isUserInteractionEnabled = model.phase == .ready
        view.updateGuides()
        view.accessibilityValue = (model.isPreviewing ? "Loading frame" : "Frame \(model.selection?.position ?? 0)") + (model.isCropping ? " Cropping" : "")
    }
    static func dismantleUIView(_ view: FramePreviewView, coordinator: ()) {
        view.cancelFrameGesture()
        view.onStep = nil; view.onBegin = nil; view.onMove = nil; view.onEnd = nil; view.onCancel = nil
        view.onToggleCrop = nil; view.onCropBegin = nil; view.onCropMove = nil; view.onCropEnd = nil
    }
}


/// Native SwiftUI preference propagates to the fullScreenCover's hosting
/// controller (no competing UIKit override). This requests priority, not a ban.
enum CropEdgePolicy {
    static func edges(landscape: Bool, cropping: Bool, active: Bool) -> Edge.Set {
        landscape && cropping && active ? .all : []
    }
    /// Read-only evidence of the actual presented hosting/container hierarchy.
    /// Never installs a second override or changes system gesture dispatch.
    @MainActor static func resolvedEdges(window: UIWindow?) -> UIRectEdge {
        guard var controller = window?.rootViewController else { return [] }
        while let presented = controller.presentedViewController { controller = presented }
        while let child = controller.childForScreenEdgesDeferringSystemGestures, child !== controller { controller = child }
        return controller.preferredScreenEdgesDeferringSystemGestures
    }
}

struct FrameExtractionScreen: View {
    @ObservedObject var model: FrameExtractionModel
    let onClose: (Int) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastOrientation = UIDeviceOrientation.unknown
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                FramePreview(model: model).ignoresSafeArea()
                if !model.isCropping {
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 0)
                        footer
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }
                if model.phase == .loading || (model.preview == nil && model.isPreviewing) {
                    ProgressView().tint(.white).allowsHitTesting(false)
                } else if model.phase == .preparing || model.phase == .saving {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(model.progress).font(.caption).accessibilityIdentifier("frameProgress")
                    }.padding().mediaGlass().allowsHitTesting(false)
                } else if let error = model.error {
                    VStack(spacing: 8) {
                        Text(error).font(.callout).multilineTextAlignment(.center).accessibilityIdentifier("frameError")
                        if model.phase == .unavailable { Button("Retry") { model.retryPreview() } }
                    }.padding().frame(maxWidth: 300).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .foregroundStyle(.white).tint(.white).background(.black)
            .statusBarHidden(landscape)
            .defersSystemGestures(on: CropEdgePolicy.edges(landscape: landscape, cropping: model.isCropping, active: scenePhase == .active))
            .onChange(of: geometry.size) { _, _ in model.cancelGestures() }
        }
        .onAppear { lastOrientation = UIDevice.current.orientation; model.prepare() }
        .onChange(of: model.savedCount) { _, count in if count > 0 { onClose(count) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.backgrounded() } }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            guard [.portrait, .landscapeLeft, .landscapeRight].contains(orientation), orientation != lastOrientation else { return }
            lastOrientation = orientation; model.cancelGestures()
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { if model.canClose { onClose(0) } } label: {
                Image(systemName: "xmark").frame(width: 48, height: 48).mediaGlass()
            }.accessibilityLabel("Cancel").accessibilityIdentifier("cancelFrames").disabled(!model.canClose)
            Spacer(minLength: 0)
            Text(model.selection?.summary ?? "Frames")
                .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 14).frame(minHeight: 44).mediaGlass().accessibilityIdentifier("frameSummary")
            Spacer(minLength: 0)
            Button { model.save() } label: {
                Image(systemName: "checkmark").frame(width: 48, height: 48).mediaGlass()
            }.accessibilityLabel("Done").accessibilityIdentifier("saveFrames").disabled(!model.canSave)
        }.buttonStyle(.plain)
    }
    private var footer: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Set Start") { model.setStart() }
                    .disabled(!model.canSetEndpoints || model.selection?.canSetStart != true)
                    .accessibilityIdentifier("setFrameStart")
                Spacer(minLength: 4)
                if !model.crop.isFull {
                    Button { model.resetCrop() } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Reset Crop").accessibilityIdentifier("resetCrop")
                }
                Spacer(minLength: 4)
                Button("Set End") { model.setEnd() }
                    .disabled(!model.canSetEndpoints || model.selection?.canSetEnd != true)
                    .accessibilityIdentifier("setFrameEnd")
            }.buttonStyle(FrameEndpointStyle()).font(.caption)
            VStack(spacing: 0) {
                HStack {
                    Text("0:00").accessibilityIdentifier("frameWindowStart")
                    Spacer()
                    Text(model.selection.map { FrameRelativeTime.text($0.times[$0.position], origin: $0.times[0]) } ?? "—")
                        .accessibilityIdentifier("framePosition")
                    Spacer()
                    Text(model.selection.map { FrameRelativeTime.text($0.times.last!, origin: $0.times[0]) } ?? "0:00")
                        .accessibilityIdentifier("frameWindowEnd")
                }.font(.caption.monospacedDigit()).padding(.horizontal, 14).padding(.top, 8)
                FrameTimeline(model: model).frame(height: 44).padding(.horizontal, 6)
            }.mediaGlass()
        }
    }
}

private struct FrameEndpointStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 14).frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule()).mediaGlass().opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.5 : 1)
    }
}
