import SwiftUI

enum SeekFeedbackStyle {
    static let columnWidth = 168.0
    static let fontSize = 21.0
    static let fadeDuration = 0.18
    static func clock(_ seconds: Double) -> String {
        let value = PlaybackPolicy.clock(seconds)
        return value.count < 5 ? "0" + value : value
    }
    static func difference(_ seconds: Double) -> String {
        guard seconds.isFinite, abs(seconds) >= 0.05 else { return "+0.0s" }
        return String(format: "%@%.1fs", seconds < 0 ? "−" : "+", abs(seconds))
    }
    static func skipCenter(in video: CGRect, forward: Bool) -> CGPoint {
        CGPoint(x: video.minX + video.width * (forward ? 0.75 : 0.25), y: video.midY)
    }
}

/// No material panel, hit-testing surface or layout contribution. The exact
/// aspect-fit picture, not the black letterbox, owns feedback placement.
struct SeekFeedbackOverlay: View {
    let preview: SeekPreview?
    let skip: SkipFeedback?
    var pictureSize = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let video = VideoGeometry.fitted(pictureSize, in: CGRect(origin: .zero, size: geometry.size))
            let scale = min(1, video.height / 80)
            ZStack(alignment: .topLeading) {
                if let preview, preview.source == .horizontal, video.width > 0 {
                    VStack(spacing: 2 * scale) {
                        Text(SeekFeedbackStyle.clock(preview.target))
                        Text(SeekFeedbackStyle.difference(preview.target - preview.origin))
                    }.font(.system(size: SeekFeedbackStyle.fontSize * scale, weight: .regular).monospacedDigit())
                        .frame(width: min(SeekFeedbackStyle.columnWidth, video.width))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .position(x: video.midX, y: video.minY + max(30 * scale, video.height * 0.25))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("seekPreview")
                        .transition(.opacity)
                }
                if let skip, video.width > 0 {
                    VStack(spacing: 3 * scale) {
                        Image(systemName: skip.forward ? "forward.fill" : "backward.fill")
                            .font(.system(size: 24 * scale, weight: .medium)).accessibilityHidden(true)
                        Text(skip.text).font(.system(size: SeekFeedbackStyle.fontSize * scale, weight: .regular).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.35).accessibilityIdentifier("skipFeedback")
                    }.frame(width: video.width * 0.45, height: min(60, video.height))
                        .position(SeekFeedbackStyle.skipCenter(in: video, forward: skip.forward))
                        .transition(.opacity)
                }
            }
        }
        .foregroundStyle(.white).shadow(color: .black.opacity(0.65), radius: 1.5, x: 0, y: 1)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: SeekFeedbackStyle.fadeDuration), value: preview?.source == .horizontal)
        .animation(reduceMotion ? nil : .easeOut(duration: SeekFeedbackStyle.fadeDuration), value: skip == nil)
    }
}
