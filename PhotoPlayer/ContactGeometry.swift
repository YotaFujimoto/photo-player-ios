import UIKit

/// A fresh measurement in one UIWindow coordinate space. This never routes input.
@MainActor
struct ContactGeometry {
    @MainActor struct Cell {
        let probe: ContactProbeView
        let frame: CGRect
        let visibleFrame: CGRect
        let presentationFrame: CGRect?
        let visible: Bool
        var number: Int { probe.number }
    }

    let point: CGPoint
    let cells: [Cell]
    let controls: [String]
    let receiver: String
    let windowBounds: CGRect
    let registered: Int

    init(point: CGPoint, window: UIWindow, probes: [ContactProbeView], receiver: UIView?) {
        self.point = point
        self.windowBounds = window.bounds
        self.registered = probes.count
        self.receiver = Self.receiverDescription(receiver, in: window)
        let measurements = probes.filter { $0.window === window }.map { probe in
            let frame = probe.convert(probe.bounds, to: window)
            var visibleFrame = frame.intersection(window.bounds)
            var ancestor = probe.superview
            while let view = ancestor {
                if view.clipsToBounds {
                    visibleFrame = visibleFrame.intersection(view.convert(view.bounds, to: window))
                }
                ancestor = view.superview
            }
            let presentationFrame: CGRect?
            if let layer = probe.layer.presentation(), let root = window.layer.presentation() {
                presentationFrame = layer.convert(layer.bounds, to: root)
            } else { presentationFrame = nil }
            return Cell(probe: probe, frame: frame, visibleFrame: visibleFrame, presentationFrame: presentationFrame,
                        visible: probe.isVisibleInHierarchy && !visibleFrame.isNull && !visibleFrame.isEmpty)
        }
        cells = measurements.filter { $0.probe.control == nil }
        controls = measurements.filter { $0.visible && $0.visibleFrame.contains(point) }
            .compactMap { $0.probe.control }.sorted()
    }

    var candidates: [Cell] { cells.filter { $0.visible && $0.visibleFrame.contains(point) } }
    // Never silently pick the first registered cell when geometry is ambiguous.
    var uniqueCell: Cell? { controls.isEmpty && candidates.count == 1 ? candidates[0] : nil }

    var evidence: String {
        let hits = candidates
        let raw = cells.filter { $0.frame.contains(point) }
        let nearest = cells.filter(\.visible).sorted {
            Self.distance(point, to: $0.visibleFrame) < Self.distance(point, to: $1.visibleFrame)
        }.prefix(3)
        var details: [Cell] = []
        for cell in Array(hits.prefix(4)) + Array(raw.prefix(4)) + Array(nearest) {
            if !details.contains(where: { $0.probe === cell.probe }) { details.append(cell) }
        }
        let frames = details.prefix(6).map {
            "V\($0.number){p=\($0.probe.serial),rev=\($0.probe.identityRevision),layout=\($0.probe.layoutRevision),frame=\(Self.rect($0.frame)),clip=\(Self.rect($0.visibleFrame)),presentation=\($0.presentationFrame.map { Self.rect($0) } ?? "unavailable"),visible=\($0.visible)}"
        }.joined(separator: ";")
        return "point=\(Self.point(point)) window=\(Self.rect(windowBounds)) candidates=\(Self.videos(hits)) rawCandidates=\(Self.videos(raw)) controls=[\(controls.joined(separator: ","))] registered=\(registered) receiver=\(receiver) cells=[\(frames)]"
    }

    private static func videos(_ cells: [Cell]) -> String {
        "[" + cells.map { "V\($0.number)" }.joined(separator: ",") + "]"
    }
    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(max(rect.minX - point.x, 0), point.x - rect.maxX),
              max(max(rect.minY - point.y, 0), point.y - rect.maxY))
    }
    private static func point(_ value: CGPoint) -> String { String(format: "(%.1f,%.1f)", value.x, value.y) }
    static func rect(_ value: CGRect) -> String {
        guard !value.isNull, !value.isInfinite else { return "empty" }
        return String(format: "(%.1f,%.1f,%.1f,%.1f)", value.minX, value.minY, value.width, value.height)
    }
    private static func receiverDescription(_ receiver: UIView?, in window: UIWindow) -> String {
        guard let receiver else { return "none" }
        var chain: [String] = []
        var ancestor: UIView? = receiver
        while let view = ancestor, chain.count < 6 {
            // Class names only: never description, labels, accessibility values,
            // object addresses, Photos identifiers, or user text.
            let name = String(NSStringFromClass(type(of: view)).prefix(while: { $0 != "<" }).prefix(96))
            chain.append("\(name){frame=\(rect(view.convert(view.bounds, to: window))),interaction=\(view.isUserInteractionEnabled),hidden=\(view.isHidden),alpha=\(String(format: "%.2f", view.alpha))}")
            ancestor = view.superview
        }
        return chain.joined(separator: ">")
    }
}
