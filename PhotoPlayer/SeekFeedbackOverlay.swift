import SwiftUI

enum SeekFeedbackStyle {
    static let fontSize = 16.0
    static let fadeDuration = 0.18
    static func clock(_ seconds: Double) -> String {
        let value = PlaybackPolicy.clock(seconds)
        return value.count < 5 ? "0" + value : value
    }
    static func difference(_ seconds: Double) -> String {
        guard seconds.isFinite, abs(seconds) >= 0.05 else { return "+0.0s" }
        return String(format: "%@%.1fs", seconds < 0 ? "−" : "+", abs(seconds))
    }
    // Use the SF glyph's intrinsic dimensions at Build 16's 24pt font, never
    // the former 44pt transparent container, as the movement/scale reference.
    private static let originalGlyph = UIImage(systemName: "goforward.10",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))!.size
    // Frozen Build 17 geometry: derive centers BEFORE resizing the glyph.
    static func build17SkipFrame(in video: CGRect, forward: Bool, playButton: CGRect? = nil) -> CGRect {
        let oldContainer = max(0, min(44, video.height - 4, video.width * 0.3))
        let oldScale = min(24, oldContainer * 0.55) / 24
        let oldGlyph = CGSize(width: originalGlyph.width * oldScale, height: originalGlyph.height * oldScale)
        let inset = min(12, max(0, (video.width - oldContainer) / 4))
        let desiredCenter = forward ? video.maxX - inset - oldContainer / 2 - oldGlyph.width
            : video.minX + inset + oldContainer / 2 + oldGlyph.width
        var minX = forward ? video.midX + 4 : video.minX + 2
        var maxX = forward ? video.maxX - 2 : video.midX - 4
        if let playButton, playButton.minY < video.midY + oldGlyph.height * 0.75,
           playButton.maxY > video.midY - oldGlyph.height * 0.75 {
            if forward { minX = max(minX, playButton.maxX + 8) }
            else { maxX = min(maxX, playButton.minX - 8) }
        }
        let scale = max(0, min(1.5, (maxX - minX) / max(1, oldGlyph.width), (video.height - 4) / max(1, oldGlyph.height)))
        let size = CGSize(width: oldGlyph.width * scale, height: oldGlyph.height * scale)
        guard size.width > 0 else { return CGRect(x: video.minX, y: video.midY, width: 0, height: 0) }
        let center = min(max(desiredCenter, minX + size.width / 2), maxX - size.width / 2)
        return CGRect(x: center - size.width / 2, y: video.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func skipFrame(in video: CGRect, canvas: CGRect, forward: Bool, playButton: CGRect? = nil) -> CGRect {
        let baseline = build17SkipFrame(in: video, forward: forward, playButton: playButton)
        var center = baseline.midX
        if video.width > video.height {
            // Transpose this material's aspect ratio, then fit its portrait
            // counterpart in this canvas. No previous video or orientation cache.
            let reference = VideoGeometry.fitted(CGSize(width: video.height, height: video.width), in: canvas)
            var referenceGlyph = build17SkipFrame(in: reference, forward: forward, playButton: playButton)
            // Extremely narrow references may have no space beside the button.
            // Derive the ratio without that obstruction, then fit the real glyph.
            if referenceGlyph.isEmpty { referenceGlyph = build17SkipFrame(in: reference, forward: forward) }
            let ratio = (referenceGlyph.midX - reference.midX) / max(1, reference.width / 2)
            center = video.midX + ratio * video.width / 2
        }
        var size = CGSize(width: baseline.width * 0.9, height: baseline.height * 0.9)
        // Keep the requested center/ratio even on unusual aspect ratios. Reduce
        // only if required for containment, rather than sliding toward the button.
        var available = min(center - video.minX, video.maxX - center)
        if let playButton, playButton.minY < video.midY + size.height / 2,
           playButton.maxY > video.midY - size.height / 2 {
            available = min(available, forward ? center - playButton.maxX - 8 : playButton.minX - center - 8)
        }
        let fit = max(0, min(1, 2 * available / max(1, size.width)))
        size.width *= fit; size.height *= fit
        return CGRect(x: center - size.width / 2, y: video.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func horizontalFrame(video: CGRect, canvas: CGRect, playButton: CGRect?, text: String = "+0.0s") -> CGRect {
        let textWidth = (text as NSString).size(withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)]).width
        let width = min(ceil(textWidth) + 16, canvas.width), height = min(32, canvas.height)
        var y = video.minY + video.height * 0.25 - height / 2
        if let playButton {
            // The actual button anchor includes its safe-area offset. A short
            // picture uses existing letterbox; neither picture nor button moves.
            y = min(y, playButton.minY - 10 - height)
        }
        y = min(max(y, canvas.minY + 4), canvas.maxY - height - 4)
        return CGRect(x: min(max(video.midX - width / 2, canvas.minX), canvas.maxX - width),
                      y: y, width: width, height: height)
    }
}

struct PlayerButtonBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Display-only overlay: no layout contribution and no input surface.
struct SeekFeedbackOverlay: View {
    let preview: SeekPreview?
    let skip: SkipFeedback?
    var pictureSize = CGSize.zero
    var playButtonFrame: CGRect? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let canvas = CGRect(origin: .zero, size: geometry.size)
            let video = VideoGeometry.fitted(pictureSize, in: canvas)
            ZStack(alignment: .topLeading) {
                if let preview, preview.source == .horizontal, video.width > 0 {
                    let text = SeekFeedbackStyle.difference(preview.target - preview.origin)
                    let frame = SeekFeedbackStyle.horizontalFrame(video: video, canvas: canvas, playButton: playButtonFrame, text: text)
                    Text(text)
                        .font(.system(size: SeekFeedbackStyle.fontSize, weight: .regular).monospacedDigit())
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                        .frame(width: frame.width, height: frame.height).transientMaterial()
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityIdentifier("seekPreview")
                        .transition(.opacity)
                }
                if let skip, video.width > 0 {
                    let frame = SeekFeedbackStyle.skipFrame(in: video, canvas: canvas, forward: skip.forward, playButton: playButtonFrame)
                    AnimatedSkipSymbol(feedback: skip)
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityElement(children: .ignore).accessibilityAddTraits(.isImage)
                        .accessibilityLabel(skip.text).accessibilityIdentifier("skipFeedback")
                        .transition(.opacity)
                }
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: SeekFeedbackStyle.fadeDuration), value: preview != nil)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : SeekFeedbackStyle.fadeDuration), value: skip == nil)
    }
}
