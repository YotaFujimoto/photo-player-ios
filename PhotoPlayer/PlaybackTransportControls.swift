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
        VStack(spacing: 12) {
            HStack {
                Text(PlaybackPolicy.clock(state.position)).accessibilityIdentifier("playbackPosition")
                Spacer()
                Text(PlaybackPolicy.clock(state.duration)).accessibilityIdentifier("playbackDuration")
            }.font(.caption.monospacedDigit())
            SeekBar(position: state.position, duration: state.duration,
                    enabled: state.isReady && state.duration > 0, cancellationID: state.cancellationID,
                    onBegin: actions.begin, onChange: actions.change, onCommit: actions.commit, onCancel: actions.cancel)
                .frame(height: 44)
            HStack {
                if fullscreen { playButton.buttonStyle(TrackedPlayerButtonStyle(onPress: { actions.pressing("playPause", $0) })) }
                else { playButton.buttonStyle(.borderedProminent) }
                Spacer()
                if fullscreen {
                    Button { ratePresentation.wrappedValue = true } label: { rateLabel }
                        .buttonStyle(TrackedPlayerButtonStyle(onPress: { actions.pressing("rateMenu", $0) }))
                        .popover(isPresented: ratePresentation) {
                            VStack(spacing: 0) {
                                ForEach(PlaybackPolicy.rates, id: \.self) { rate in
                                    Button {
                                        actions.setRate(rate)
                                        ratePresentation.wrappedValue = false
                                    } label: {
                                        HStack {
                                            Text(String(format: "%g×", rate))
                                            Spacer()
                                            if rate == state.selectedRate { Image(systemName: "checkmark").accessibilityHidden(true) }
                                        }.padding(.horizontal, 16).frame(height: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(rate < 1 && !state.canPlaySlow)
                                }
                            }.frame(width: 150).padding(.vertical, 4)
                                // A hierarchical .primary would inherit the
                                // white video chrome; use the semantic color.
                                .foregroundStyle(Color.primary)
                                .presentationCompactAdaptation(.popover)
                        }
                        .disabled(!state.isReady).accessibilityIdentifier("rateMenu")
                        .accessibilityLabel("Playback speed").accessibilityValue(String(format: "%g×", state.selectedRate))
                } else {
                    Menu {
                        ForEach(PlaybackPolicy.rates, id: \.self) { rate in
                            Button(String(format: "%g×", rate)) { actions.setRate(rate) }
                                .disabled(rate < 1 && !state.canPlaySlow)
                        }
                    } label: { rateLabel }
                    .disabled(!state.isReady).accessibilityIdentifier("rateMenu")
                        .accessibilityLabel("Playback speed").accessibilityValue(String(format: "%g×", state.selectedRate))
                }
            }
            // Normal controls have no status row, hidden placeholder or reserved space.
            if diagnostics {
                Text(state.stateText).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("playerState")
            }
        }
    }

    private var rateLabel: some View {
        Text(String(format: "%g×", state.selectedRate)).frame(minWidth: 44, minHeight: 44)
    }
    private var playButton: some View {
        Button(action: actions.togglePlayback) {
            Label(state.showsPause ? "Pause" : "Play", systemImage: state.showsPause ? "pause.fill" : "play.fill")
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }.disabled(!state.isReady)
            .accessibilityIdentifier("playPause").accessibilityValue(state.stateText)
    }
}
