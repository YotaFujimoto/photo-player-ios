import SwiftUI
import CoreMedia

@MainActor final class FrameExtractionModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, preparing, saving, saved, unavailable, uncertain }
    @Published private(set) var phase = Phase.loading
    @Published private(set) var selection: FrameSelection?
    @Published private(set) var preview: CGImage?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isInteracting = false
    @Published private(set) var progress = ""
    @Published private(set) var error: String?
    @Published private(set) var savedCount = 0
    let source: any FrameProviding
    let fileStem: String
    let entryTime: CMTime
    var onDiagnostic: ((String) -> Void)?
    private let writer: any FramePhotoWriting
    private var setupTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pending: (Int, Int)?
    private var requestedIndex: Int?
    private var revision = 0
    private var diagnosticRevision = 0
    private var closed = false
    private var interactionOrigin: Double?
    var canSetEndpoints: Bool { phase == .ready && !isPreviewing && !isInteracting && preview != nil }
    var canSave: Bool { canSetEndpoints }
    var canClose: Bool { phase != .saving }
    var displayedTime: CMTime? { selection.map { $0.times[$0.position] } }

    init(source: any FrameProviding, fileStem: String, entryTime: CMTime = .zero, writer: (any FramePhotoWriting)? = nil) {
        self.source = source; self.fileStem = fileStem
        self.entryTime = entryTime
        self.writer = writer ?? PhotoFrameWriter()
        FrameWorkspace.pruneAbandoned()
    }
    func prepare() {
        guard setupTask == nil, phase == .loading, !closed else { return }
        setupTask = Task { [weak self] in
            guard let self else { return }
            defer { setupTask = nil }
            do {
                let times = try await source.catalogue()
                try Task.checkCancellation()
                guard !closed else { return }
                selection = FrameSelection(times: times)
                phase = .ready
                request(index: 0)
                await recordDiagnostic(stage: "catalogue-ready")
            } catch {
                guard !closed else { return }
                self.error = message(error); phase = .unavailable
                await recordDiagnostic(stage: "catalogue-failed", error: error)
            }
        }
    }
    func request(index: Int) {
        guard phase == .ready, let selection, !closed else { return }
        let index = min(max(index, 0), selection.times.count - 1)
        if requestedIndex == index && (isPreviewing || preview != nil) { return }
        requestedIndex = index
        revision += 1
        pending = (index, revision)
        isPreviewing = true
        error = nil
        guard previewTask == nil else { return }
        previewTask = Task { [weak self] in
            guard let self else { return }
            // One decode in flight and one replaceable destination. Never show
            // an old result, even when it completes after a newer pointer move.
            while let (index, token) = pending, !closed {
                pending = nil
                do {
                    guard let time = self.selection?.times[index] else { break }
                    let result = try await source.image(at: time, fullSize: false)
                    guard !closed, revision == token else { continue }
                    guard CMTimeCompare(result.time, time) == 0 else { throw FrameExportError.mismatch }
                    preview = result.image
                    self.selection?.show(index)
                    isPreviewing = false
                    await recordDiagnostic(stage: "preview-ready")
                } catch {
                    guard !closed, revision == token else { continue }
                    self.error = message(error)
                    isPreviewing = false; requestedIndex = nil
                    await recordDiagnostic(stage: "preview-failed", error: error)
                }
            }
            previewTask = nil
        }
    }
    func move(to seconds: Double) { if let selection { request(index: selection.nearest(to: seconds)) } }
    func step(forward: Bool) {
        guard let selection, phase == .ready, !isInteracting else { return }
        request(index: (requestedIndex ?? selection.position) + (forward ? 1 : -1))
    }
    func beginInteraction() -> Bool {
        guard phase == .ready, !isInteracting, let displayedTime else { return false }
        interactionOrigin = displayedTime.seconds; isInteracting = true
        return true
    }
    func swipe(translation: Double, width: Double) {
        guard let origin = interactionOrigin, width > 0 else { return }
        move(to: origin + translation / width * Self.swipeSecondsPerWidth)
    }
    static let swipeSecondsPerWidth = 1.0
    func finishInteraction() { isInteracting = false; interactionOrigin = nil }
    func cancelInteraction() {
        let origin = interactionOrigin
        finishInteraction()
        if let origin { requestedIndex = nil; move(to: origin) }
    }
    func setStart() { if canSetEndpoints { selection?.setStart() } }
    func setEnd() { if canSetEndpoints { selection?.setEnd() } }

    func save() {
        guard canSave, let snapshot = selection else { return }
        phase = .preparing; error = nil; progress = "Preparing photos…"
        let operation = UUID()
        let times = snapshot.indices.map { snapshot.times[$0] }
        let start = snapshot.times[snapshot.start]
        saveTask = Task { [weak self] in
            guard let self else { return }
            var directory: URL?
            var background = UIBackgroundTaskIdentifier.invalid
            defer {
                if let directory { FrameWorkspace.remove(directory) }
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
                saveTask = nil
            }
            do {
                try await writer.authorize()
                try Task.checkCancellation()
                guard !closed else { return }
                let folder = try FrameWorkspace.create(id: operation)
                directory = folder
                var photos: [PreparedPhoto] = []
                for (offset, time) in times.enumerated() {
                    try Task.checkCancellation()
                    progress = "Preparing \(offset + 1)/\(times.count)…"
                    let name = FrameFileName.make(stem: fileStem, start: start, operation: operation, ordinal: offset + 1, actual: time)
                    let url = folder.appendingPathComponent(name)
                    let actual = try await source.writeJPEG(at: time, to: url)
                    guard CMTimeCompare(actual, time) == 0 else { throw FrameExportError.mismatch }
                    photos.append(PreparedPhoto(url: url, filename: name))
                }
                try Task.checkCancellation()
                guard !closed else { return }
                phase = .saving; progress = "Saving to Photos…"
                background = UIApplication.shared.beginBackgroundTask(withName: "Save frame photos", expirationHandler: nil)
                // Once registration begins, cancellation cannot claim that no
                // photos were created. Await the real transaction result.
                try await writer.save(photos)
                savedCount = photos.count; phase = .saved
                await recordDiagnostic(stage: "saved")
            } catch {
                guard !closed else { return }
                self.error = error is CancellationError ? "Preparation stopped. Tap Done to try again." : message(error)
                phase = (error as? FrameExportError) == .uncertain ? .uncertain : .ready
                await recordDiagnostic(stage: "save-failed", error: error)
            }
        }
    }
    func backgrounded() {
        cancelInteraction()
        if phase == .preparing { saveTask?.cancel() }
    }
    func retryPreview() {
        guard phase == .ready || phase == .unavailable else { return }
        if phase == .unavailable { phase = .loading; error = nil; prepare() }
        else {
            let index = requestedIndex ?? selection?.position ?? 0
            requestedIndex = nil; request(index: index)
        }
    }
    func close() {
        guard canClose else { return }
        closed = true; revision += 1; pending = nil
        setupTask?.cancel(); previewTask?.cancel(); saveTask?.cancel()
        Task { await source.cancel() }
    }
    private func recordDiagnostic(stage: String, error: Error? = nil) async {
        guard let onDiagnostic else { return }
        diagnosticRevision += 1
        let token = diagnosticRevision
        let report = await source.diagnosticReport()
        guard diagnosticRevision == token else { return }
        // Whitelisted reason only. Never forward localized errors or URLs.
        let reason = (error as? FrameExportError)?.rawValue ?? (error == nil ? "none" : error is CancellationError ? "cancelled" : "operation-failed")
        onDiagnostic(report + "\noperationStage=\(stage) reason=\(reason)")
    }
    private func message(_ error: Error) -> String {
        if let known = error as? FrameExportError { return known.localizedDescription }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return FrameExportError.storage.localizedDescription }
        return "Frame unavailable. Check access and try again."
    }
}
