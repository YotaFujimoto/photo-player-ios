import SwiftUI
import Photos

private struct VideoSelection: Identifiable {
    let video: LibraryVideo
    let operation: Int
    // Preserve build 4/5's PhotoKit identity; the operation number is evidence,
    // not a change to fullScreenCover's presentation identity.
    var id: String { video.id }
}

struct LibraryScreen: View {
    @StateObject private var library = VideoLibrary()
    // Only the diagnostic panels observe these counters; recording a contact
    // must not rebuild every button in the library.
    let trace: SelectionTrace
    @State private var selection: VideoSelection?
    @State private var selectionDiagnostics = ProcessInfo.processInfo.arguments.contains("--selection-diagnostics")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(trace: SelectionTrace) { self.trace = trace }

    var body: some View {
        NavigationStack {
            Group {
                if library.canRead {
                    VStack(spacing: 8) {
                        if library.authorization == .limited {
                            HStack {
                                Text("Limited access").font(.caption)
                                Spacer()
                                Button("Manage") { library.changeLimitedSelection() }
                            }.padding(.horizontal)
                        }
                        if library.videos.isEmpty {
                            ContentUnavailableView("No videos", systemImage: "video",
                                description: Text("Add videos to Photos or check access."))
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 16) {
                                    ForEach(library.videos) { video in
                                        Button {
                                            let operation = trace.accept(video.diagnosticNumber)
                                            selection = VideoSelection(video: video, operation: operation)
                                            trace.selectionWritten(selection?.operation, reason: "Button.action")
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                VideoThumbnail(video: video, manager: library.thumbnails, revision: library.revision)
                                                    .allowsHitTesting(false)
                                                if selectionDiagnostics {
                                                    Text("Video \(video.diagnosticNumber)")
                                                        .font(.caption).foregroundStyle(.primary)
                                                }
                                            }
                                            // The cell owns one rectangular tap area. Image clipping
                                            // controls drawing, not the scaled image's hit-test extent.
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(.interaction, Rectangle())
                                            .background { ContactProbe(number: video.diagnosticNumber, trace: trace).allowsHitTesting(false) }
                                            .overlay {
                                                if selectionDiagnostics {
                                                    Rectangle().stroke(.orange, lineWidth: 1).allowsHitTesting(false)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("videoCard.\(video.diagnosticNumber)")
                                        .accessibilityLabel(selectionDiagnostics ? "Video \(video.diagnosticNumber)" : "Video, \(PlaybackPolicy.clock(video.asset.duration))")
                                        .accessibilityValue(video.dimensions)
                                    }
                                }.padding()
                            }
                        }
                        if selectionDiagnostics { SelectionTracePanel(trace: trace, location: "library") }
                        if selection != nil {
                            ProgressView("Opening…").accessibilityIdentifier("openingVideo")
                        }
                    }
                } else if library.authorization == .notDetermined {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Your videos", systemImage: "photo.on.rectangle",
                            description: Text("Allow Photos access to browse and play videos."))
                        Button("Allow access") { Task { await library.requestAccess() } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("authorizePhotos")
                    }.padding()
                } else {
                    VStack {
                        ContentUnavailableView("Photos access needed", systemImage: "lock",
                            description: Text("Allow access in Settings."))
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(.bordered)
                    }.padding()
                }
            }
            .navigationTitle("Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    selectionDiagnostics.toggle()
                    trace.diagnosticsChanged(selectionDiagnostics)
                } label: {
                    Image(systemName: "square.dashed").frame(width: 28, height: 28)
                        .traceControl("diagnostics.toggle", trace: trace)
                }.accessibilityIdentifier("selectionDiagnostics")
                    .accessibilityLabel(selectionDiagnostics ? "Hide selection diagnostics" : "Show selection diagnostics")
                Button {
                    trace.controlAction("library.refresh"); library.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                        .traceControl("library.refresh", trace: trace)
                }.accessibilityIdentifier("refreshLibrary").accessibilityLabel("Refresh videos")
            }
        }
        .task { trace.diagnosticsChanged(selectionDiagnostics, initial: true); library.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { library.refresh() } }
        .onChange(of: library.revision) { _, _ in
            if let selection, !library.videos.contains(where: { $0.id == selection.id }) {
                self.selection = nil
                trace.selectionWritten(nil, reason: "asset-missing-after-library-refresh")
            }
        }
        .onChange(of: selection?.operation) { old, new in trace.selectionObserved(old: old, new: new) }
        .fullScreenCover(item: presentationSelection, onDismiss: { trace.dismissed() }) { selection in
            PlayerScreen(video: selection.video, selectionDiagnostics: selectionDiagnostics,
                         selectionTrace: trace, selectionOperation: selection.operation)
        }
    }

    private var presentationSelection: Binding<VideoSelection?> {
        Binding(get: { selection }, set: { proposed in
            trace.bindingWrite(proposed?.operation)
            selection = proposed
            trace.selectionWritten(selection?.operation, reason: "fullScreenCover.binding")
        })
    }
}
