import SwiftUI

enum SeekFeedbackStyle {
    static let columnWidth = 112.0
    static let fontSize = 14.0
    static let fadeDuration = 0.18
    static func clock(_ seconds: Double) -> String {
        let value = PlaybackPolicy.clock(seconds)
        return value.count < 5 ? "0" + value : value
    }
    static func difference(_ seconds: Double) -> String {
        guard seconds.isFinite, abs(seconds) >= 0.05 else { return "+0.0s" }
        return String(format: "%@%.1fs", seconds < 0 ? "−" : "+", abs(seconds))
    }
}

/// Text only: no material panel, no hit-testing surface, no layout contribution.
struct SeekFeedbackOverlay: View {
    let preview: SeekPreview?
    let skip: SkipFeedback?

    var body: some View {
        ZStack {
            if let preview, preview.source == .horizontal {
                VStack(spacing: 2) {
                    Text(SeekFeedbackStyle.clock(preview.target))
                    Text(SeekFeedbackStyle.difference(preview.target - preview.origin))
                }
                .font(.system(size: SeekFeedbackStyle.fontSize, weight: .regular, design: .monospaced))
                .frame(width: SeekFeedbackStyle.columnWidth)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("seekPreview")
                .transition(.opacity)
            }
            if let skip {
                HStack {
                    if skip.forward { Spacer(minLength: 0) }
                    VStack(spacing: 3) {
                        Image(systemName: skip.forward ? "forward.fill" : "backward.fill")
                            .font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                        Text(skip.text).font(.system(size: 14, weight: .regular, design: .monospaced))
                            .accessibilityIdentifier("skipFeedback")
                    }.padding(.horizontal, 26)
                    if !skip.forward { Spacer(minLength: 0) }
                }.transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.65), radius: 1.5, x: 0, y: 1)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: SeekFeedbackStyle.fadeDuration), value: preview?.source == .horizontal)
        .animation(.easeOut(duration: SeekFeedbackStyle.fadeDuration), value: skip == nil)
    }
}
