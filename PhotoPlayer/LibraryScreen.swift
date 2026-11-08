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
    @State private var trace = SelectionTrace()
    @State private var selection: VideoSelection?
    @State private var selectionDiagnostics = ProcessInfo.processInfo.arguments.contains("--selection-diagnostics")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if library.canRead {
                    VStack(spacing: 8) {
                        if library.authorization == .limited {
                            HStack {
                                Text("選択した動画のみ").font(.caption)
                                Spacer()
                                Button("選択を変更") { library.changeLimitedSelection() }
                            }.padding(.horizontal)
                        }
                        if library.videos.isEmpty {
                            ContentUnavailableView("動画がありません", systemImage: "video",
                                description: Text("写真ライブラリに動画を追加するか、アクセスできる動画の選択を確認してください。"))
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
                                                Text(selectionDiagnostics ? "動画 \(video.diagnosticNumber)" :
                                                    (video.asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "動画"))
                                                    .font(.caption).foregroundStyle(.primary)
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
                                        .accessibilityValue(video.dimensions)
                                    }
                                }.padding()
                            }
                        }
                        Text("iCloudの動画は選択時に取得します。動画の変更・削除は行いません。")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                        if selectionDiagnostics { SelectionTracePanel(trace: trace, location: "library") }
                        if selection != nil {
                            ProgressView("動画を開いています…").accessibilityIdentifier("openingVideo")
                        }
                    }
                } else if library.authorization == .notDetermined {
                    VStack(spacing: 20) {
                        ContentUnavailableView("写真の動画を再生", systemImage: "photo.on.rectangle",
                            description: Text("動画を一覧表示するために、写真ライブラリへのアクセスを許可してください。"))
                        Button("動画へのアクセスを許可") { Task { await library.requestAccess() } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("authorizePhotos")
                    }.padding()
                } else {
                    VStack {
                        ContentUnavailableView("写真へのアクセスがありません", systemImage: "lock",
                            description: Text("設定で写真へのアクセスを許可してください。端末の利用制限がある場合は管理設定も確認してください。"))
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(.bordered)
                    }.padding()
                }
            }
            .navigationTitle("動画")
            .toolbar {
                Button {
                    selectionDiagnostics.toggle()
                    trace.diagnosticsChanged(selectionDiagnostics)
                } label: {
                    Image(systemName: "square.dashed").frame(width: 28, height: 28)
                        .traceControl("diagnostics.toggle", trace: trace)
                }.accessibilityIdentifier("selectionDiagnostics")
                    .accessibilityLabel(selectionDiagnostics ? "選択確認を終了" : "選択確認")
                Button {
                    trace.controlAction("library.refresh"); library.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                        .traceControl("library.refresh", trace: trace)
                }.accessibilityIdentifier("refreshLibrary").accessibilityLabel("更新")
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
