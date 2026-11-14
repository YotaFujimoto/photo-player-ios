import SwiftUI

/// Information only. Lifecycle belongs to the caller (saving is state-driven,
/// success has its existing timer). Never used for buttons or transport controls.
private struct TransientMaterial: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            // The media canvas and foreground are always black/white, regardless
            // of the library's appearance. Keep this preference local to the HUD.
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }
}

extension View {
    func transientMaterial() -> some View { modifier(TransientMaterial()) }
}
