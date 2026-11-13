import SwiftUI

/// Presentation inputs are separate from AVPlayer so every loading/buffering
/// state can be measured with the same production controls in layout tests.
struct PlaybackTransportState {
    var position = 0.0
    var duration = 0.0
    var isReady = false
    var canPlaySlow = false
    var showsPause = false
    var selectedRate: Float = 1
    var stateText = "Loading…"
    var cancellationID = 0
}

struct PlaybackTransportActions {
    var begin: () -> Bool = { false }
    var change: (Double) -> Void = { _ in }
    var commit: () -> Void = {}
    var cancel: () -> Void = {}
    var togglePlayback: () -> Void = {}
    var setRate: (Float) -> Void = { _ in }
    var pressing: (String, Bool) -> Void = { _, _ in }
}

struct PlaybackTransportControls: View {
    let state: PlaybackTransportState
    var diagnostics = false
    var fullscreen = false
    var ratePresentation: Binding<Bool> = .constant(false)
    var actions = PlaybackTransportActions()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Button { ratePresentation.wrappedValue = true } label: { rateLabel.mediaGlass() }
                    .buttonStyle(TrackedPlayerButtonStyle(onPress: { actions.pressing("rateMenu", $0) }))
                    .popover(isPresented: ratePresentation) {
                        VStack(spacing: 0) {
                            ForEach(PlaybackPolicy.rates, id: \.self) { rate in
                                Button {
                                    actions.setRate(rate); ratePresentation.wrappedValue = false
                                } label: {
                                    HStack {
                                        Text(String(format: "%g×", rate))
                                        Spacer()
                                        if rate == state.selectedRate { Image(systemName: "checkmark").accessibilityHidden(true) }
                                    }.padding(.horizontal, 16).frame(height: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(rate < 1 && !state.canPlaySlow)
                            }
                        }.frame(width: 150).padding(.vertical, 4).foregroundStyle(Color.primary)
                            .presentationCompactAdaptation(.popover)
                    }
                    .disabled(!state.isReady).accessibilityIdentifier("rateMenu")
                    .accessibilityLabel("Playback speed").accessibilityValue(String(format: "%g×", state.selectedRate))
            }
            HStack(spacing: 8) {
                // Reserve the longest clock for this asset. Changing 9:59 to
                // 10:00 or 59:59 to 1:00:00 must not resize the UIControl while
                // it tracks a finger (a real resize correctly cancels tracking).
                Text(PlaybackPolicy.clock(state.duration)).hidden().fixedSize()
                    .overlay(alignment: .trailing) {
                        Text(PlaybackPolicy.clock(state.position)).fixedSize()
                            .accessibilityIdentifier("playbackPosition")
                    }
                SeekBar(position: state.position, duration: state.duration,
                        enabled: state.isReady && state.duration > 0, cancellationID: state.cancellationID,
                        onBegin: actions.begin, onChange: actions.change, onCommit: actions.commit, onCancel: actions.cancel)
                    .frame(maxWidth: .infinity).frame(height: 44)
                Text(PlaybackPolicy.clock(state.duration)).fixedSize().accessibilityIdentifier("playbackDuration")
            }.font(.caption.monospacedDigit()).lineLimit(1).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 2).mediaGlass()
            if diagnostics {
                Text(state.stateText).font(.caption).accessibilityIdentifier("playerState")
            }
        }
    }

    private var rateLabel: some View {
        Text(String(format: "%g×", state.selectedRate)).padding(.horizontal, 14).frame(minWidth: 54, minHeight: 44)
    }
}
