import SwiftUI

enum SeekFeedbackStyle {
    static let columnWidth = 96.0
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
    static func skipFrame(in video: CGRect, forward: Bool) -> CGRect {
        let diameter = max(0, min(44, video.height - 4, video.width * 0.3))
        let inset = min(12, max(0, (video.width - diameter) / 4))
        return CGRect(x: forward ? video.maxX - inset - diameter : video.minX + inset,
                      y: video.midY - diameter / 2, width: diameter, height: diameter)
    }
    static func skipCenter(in video: CGRect, forward: Bool) -> CGPoint {
        let frame = skipFrame(in: video, forward: forward)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    static func horizontalFrame(video: CGRect, canvas: CGRect, playButton: CGRect?) -> CGRect {
        let width = min(columnWidth, canvas.width), height = min(32, canvas.height)
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
                    let frame = SeekFeedbackStyle.horizontalFrame(video: video, canvas: canvas, playButton: playButtonFrame)
                    Text(SeekFeedbackStyle.difference(preview.target - preview.origin))
                        .font(.system(size: SeekFeedbackStyle.fontSize, weight: .regular).monospacedDigit())
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                        .frame(width: frame.width, height: frame.height).transientMaterial()
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityIdentifier("seekPreview")
                        .transition(.opacity)
                }
                if let skip, video.width > 0 {
                    let frame = SeekFeedbackStyle.skipFrame(in: video, forward: skip.forward)
                    Image(systemName: skip.forward ? "goforward.10" : "gobackward.10")
                        .font(.system(size: min(24, frame.height * 0.55), weight: .regular))
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(skip.text).accessibilityIdentifier("skipFeedback")
                        .transition(.opacity)
                }
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: SeekFeedbackStyle.fadeDuration), value: preview != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: SeekFeedbackStyle.fadeDuration), value: skip == nil)
    }
}
