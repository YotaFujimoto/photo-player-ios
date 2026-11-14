import SwiftUI

/// One glass surface per control group. Local dimming keeps white media controls
/// legible without dimming the canvas or nesting glass inside glass.
private struct MediaGlass: ViewModifier {
    var feedback = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                // Diagnostic branch only: isolate backdrop sampling from the
                // same media/gesture/layout path. Never distribute this view.
                // .glassEffect(.clear, in: Capsule())
                .background(.black.opacity(reduceTransparency ? 0.85 : contrast == .increased ? 0.55 : feedback ? 0.18 : 0.35), in: Capsule())
        } else {
            content.background(reduceTransparency ? .black : .black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5).allowsHitTesting(false))
        }
    }
}
extension View {
    func mediaGlass(feedback: Bool = false) -> some View { modifier(MediaGlass(feedback: feedback)) }
}
