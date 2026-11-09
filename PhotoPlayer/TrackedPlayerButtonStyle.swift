import SwiftUI

/// Pins chrome from touch-down to release/cancellation, before Button's action.
/// Unlike a container drag gesture this does not arbitrate with the seek bar.
struct TrackedPlayerButtonStyle: ButtonStyle {
    let onPress: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
            .onDisappear { onPress(false) }
    }
}
