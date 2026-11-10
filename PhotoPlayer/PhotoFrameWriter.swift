@preconcurrency import Photos
import Foundation

struct PreparedPhoto: Sendable {
    let url: URL
    let filename: String
}
@MainActor protocol FramePhotoWriting {
    func authorize() async throws
    func save(_ photos: [PreparedPhoto]) async throws
}

/// The only library mutation in the application: one atomic, add-only batch.
@MainActor final class PhotoFrameWriter: FramePhotoWriting {
    func authorize() async throws {
        let read = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if read == .authorized || read == .limited { return }
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized else { throw FrameExportError.permission }
    }

    func save(_ photos: [PreparedPhoto]) async throws {
        guard (1...10).contains(photos.count) else { throw FrameExportError.saveFailed }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                for photo in photos {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = photo.filename
                    options.shouldMoveFile = false
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: photo.url, options: options)
                }
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else if let error {
                    let ns = error as NSError
                    continuation.resume(throwing: ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError
                                        ? FrameExportError.storage : FrameExportError.saveFailed)
                } else { continuation.resume(throwing: FrameExportError.uncertain) }
            }
        }
    }
}

enum FrameWorkspace {
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("PhotoPlayerFrames", isDirectory: true) }
    static func create(id: UUID) throws -> URL {
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    static func remove(_ directory: URL) { try? FileManager.default.removeItem(at: directory) }
    static func pruneAbandoned() {
        // A killed app cannot receive Photos' completion. Leave recent batches
        // alone; normal completion removes its directory immediately.
        let old = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            guard UUID(uuidString: url.lastPathComponent) != nil,
                  let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, date < old else { continue }
            remove(url)
        }
    }
}
