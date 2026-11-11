import SwiftUI

/// One glass surface per control group. Local dimming keeps white media controls
/// legible without dimming the canvas or nesting glass inside glass.
private struct MediaGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(.black.opacity(reduceTransparency ? 0.85 : contrast == .increased ? 0.55 : 0.35), in: Capsule())
                .glassEffect(.clear, in: Capsule())
        } else {
            content.background(reduceTransparency ? .black : .black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5).allowsHitTesting(false))
        }
    }
}
extension View {
    func mediaGlass() -> some View { modifier(MediaGlass()) }
}
