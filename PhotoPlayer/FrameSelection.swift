import Foundation
import CoreMedia
import CryptoKit

/// Indices refer to measured presentation timestamps, never a nominal fps grid.
struct FrameSelection: Sendable {
    let times: [CMTime]
    private(set) var position = 0
    private(set) var start = 0
    private(set) var end: Int
    init(times: [CMTime]) {
        precondition(!times.isEmpty)
        self.times = times
        end = times.count - 1
    }
    var canSetStart: Bool { position <= end }
    var canSetEnd: Bool { position >= start }
    mutating func show(_ index: Int) { position = min(max(index, 0), times.count - 1) }
    mutating func setStart() { if canSetStart { start = position } }
    mutating func setEnd() { if canSetEnd { end = position } }
    var indices: [Int] {
        let count = end - start + 1
        if count < 10 { return Array(start...end) }
        let step = (count - 1) / 9
        return (0..<10).map { start + $0 * step }
    }
    var summary: String {
        let chosen = indices
        guard chosen.count > 1 else { return "1 frame" }
        let interval = CMTimeSubtract(times[chosen[1]], times[chosen[0]]).seconds
        return String(format: "%.3f s · %d", interval, chosen.count)
    }
    func nearest(to seconds: Double) -> Int {
        times.indices.min { abs(times[$0].seconds - seconds) < abs(times[$1].seconds - seconds) } ?? 0
    }
}

enum FrameExportError: Error, LocalizedError, Equatable {
    case unsupported, noFrames, mismatch, permission, storage, saveFailed, uncertain
    var errorDescription: String? {
        switch self {
        case .unsupported: "Frame saving requires an unedited SDR video with a constant frame rate (10–60 fps)."
        case .noFrames: "Frames unavailable. Try another position."
        case .mismatch: "Cannot match this frame accurately."
        case .permission: "Allow adding photos in Settings."
        case .storage: "Not enough storage to save photos."
        case .saveFailed: "Photos could not save. Check access and storage."
        case .uncertain: "Save result unknown. Check Photos before trying again."
        }
    }
}

enum FrameFileName {
    static func stem(original: String?, identifier: String) -> String {
        let fallback = "Video-" + SHA256.hash(data: Data(identifier.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let name = original.map { ($0 as NSString).deletingPathExtension } ?? fallback
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        var result = ""
        for scalar in name.unicodeScalars where !forbidden.contains(scalar) {
            if (result + String(scalar)).utf8.count > 70 { break }
            result.unicodeScalars.append(scalar)
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if result.isEmpty { return fallback }
        let reserved = ["CON","PRN","AUX","NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
        if reserved.contains(result.components(separatedBy: ".")[0].uppercased()) { result = "Video-" + result }
        return result
    }
    static func time(_ value: CMTime) -> String {
        let ms = max(0, Int64((value.seconds * 1000).rounded()))
        return String(format: "%02lld-%02lld-%02lld-%03lld", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
    static func make(stem: String, start: CMTime, operation: UUID, ordinal: Int, actual: CMTime) -> String {
        "\(stem)__clip-\(time(start))__set-\(operation.uuidString.lowercased())__\(String(format: "%02d", ordinal))__t-\(time(actual)).jpg"
    }
}
