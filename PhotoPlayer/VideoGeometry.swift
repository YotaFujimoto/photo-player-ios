import CoreGraphics

enum VideoGeometry {
    /// Same centered aspect-fit geometry as AVPlayerLayer and UIImageView.
    static func fitted(_ image: CGSize, in bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// Top-left normalized coordinates of the already orientation-corrected image.
struct FrameCrop: Equatable, Sendable {
    let rect: CGRect
    static let full = FrameCrop(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
    var isFull: Bool { self == .full }
    func displayed(in video: CGRect) -> CGRect {
        CGRect(x: video.minX + rect.minX * video.width, y: video.minY + rect.minY * video.height,
               width: rect.width * video.width, height: rect.height * video.height)
    }
    func pixels(width: Int, height: Int) -> CGRect {
        // Round boundaries once, not the width separately. No resize or upsample.
        let left = (rect.minX * CGFloat(width)).rounded().clamped(0, CGFloat(width - 1))
        let top = (rect.minY * CGFloat(height)).rounded().clamped(0, CGFloat(height - 1))
        let right = (rect.maxX * CGFloat(width)).rounded().clamped(left + 1, CGFloat(width))
        let bottom = (rect.maxY * CGFloat(height)).rounded().clamped(top + 1, CGFloat(height))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
    func apply(to image: CGImage) throws -> CGImage {
        if isFull { return image }
        guard let result = image.cropping(to: pixels(width: image.width, height: image.height)) else {
            throw FrameExportError.imageFailed
        }
        return result
    }
}

struct CropDrag {
    enum Target: Equatable { case move, edge(left: Bool, right: Bool, top: Bool, bottom: Bool) }
    let original: FrameCrop
    let video: CGRect
    let target: Target
    let minimum: CGSize

    init?(crop: FrameCrop, video: CGRect, point: CGPoint) {
        guard video.width > 0, video.height > 0 else { return nil }
        let frame = crop.displayed(in: video)
        // Standard touch slop around the actual edge, not a displaced handle.
        let slop = min(22, min(frame.width, frame.height) / 3)
        guard frame.insetBy(dx: -slop, dy: -slop).contains(point) else { return nil }
        let left = abs(point.x - frame.minX) <= slop
        let right = !left && abs(point.x - frame.maxX) <= slop
        let top = abs(point.y - frame.minY) <= slop
        let bottom = !top && abs(point.y - frame.maxY) <= slop
        target = left || right || top || bottom ? .edge(left: left, right: right, top: top, bottom: bottom) : .move
        original = crop; self.video = video
        // A usable handle separation in the current display, bounded for tiny images.
        minimum = CGSize(width: min(0.35, 60 / video.width), height: min(0.35, 60 / video.height))
    }
    func applying(_ delta: CGPoint) -> FrameCrop {
        let dx = delta.x / video.width, dy = delta.y / video.height
        let r = original.rect
        switch target {
        case .move:
            return FrameCrop(rect: CGRect(x: (r.minX + dx).clamped(0, 1 - r.width),
                                          y: (r.minY + dy).clamped(0, 1 - r.height), width: r.width, height: r.height))
        case let .edge(left, right, top, bottom):
            let x0 = left ? (r.minX + dx).clamped(0, r.maxX - min(r.width, minimum.width)) : r.minX
            let x1 = right ? (r.maxX + dx).clamped(r.minX + min(r.width, minimum.width), 1) : r.maxX
            let y0 = top ? (r.minY + dy).clamped(0, r.maxY - min(r.height, minimum.height)) : r.minY
            let y1 = bottom ? (r.maxY + dy).clamped(r.minY + min(r.height, minimum.height), 1) : r.maxY
            return FrameCrop(rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        }
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lower), upper) }
}
