import SwiftUI

/// Information only. Lifecycle belongs to the caller (saving is state-driven,
/// success has its existing timer). Never used for buttons or transport controls.
private struct TransientMaterial: ViewModifier {
    var circular = false
    func body(content: Content) -> some View {
        content
            .background {
                if circular { Circle().fill(.thinMaterial) }
                else { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial) }
            }
            // The media canvas and foreground are always black/white, regardless
            // of the library's appearance. Keep this preference local to the HUD.
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }
}

extension View {
    func transientMaterial(circular: Bool = false) -> some View { modifier(TransientMaterial(circular: circular)) }
}
