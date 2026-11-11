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
    static func window(_ measured: [CMTime], entry: Double) throws -> [CMTime] {
        // Missing timing before the entry must never silently move W0 forward.
        guard let first = measured.lastIndex(where: { $0.seconds <= entry + 0.000001 }) else {
            throw FrameExportError.entryFrameMissing
        }
        let end = CMTimeAdd(measured[first], CMTime(value: 3, timescale: 1))
        return Array(measured[first...].filter { CMTimeCompare($0, end) <= 0 })
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
        let interval = CMTimeSubtract(times[chosen.last!], times[chosen[0]]).seconds / Double(chosen.count - 1)
        return (FrameTiming.isVariable(times) ? "≈" : "") + String(format: "%.3f s · %d", interval, chosen.count)
    }
    func nearest(to seconds: Double) -> Int {
        times.indices.min { abs(times[$0].seconds - seconds) < abs(times[$1].seconds - seconds) } ?? 0
    }
}

enum FrameExportError: String, Error, LocalizedError, Equatable {
    case adjusted, highFrameRateCapture, timelapse, videoComposition, assetComposition
    case multipleTracks, missingFormat, codec, invalidTiming, tooManyFrames, entryFrameMissing
    case hdrRequiresNewerOS, colorProfile, colorConversion, readFailed, imageFailed, imageEncoding
    case noFrames, mismatch, permission, storage, saveFailed, uncertain
    var errorDescription: String? {
        switch self {
        case .adjusted: "Videos with photo-library adjustments are not supported yet."
        case .highFrameRateCapture: "High-frame-rate capture is not supported yet."
        case .timelapse: "Time-lapse frame saving is not supported yet."
        case .videoComposition: "This video uses unsupported playback adjustments."
        case .assetComposition: "Composed videos are not supported yet."
        case .multipleTracks: "Frame saving needs one video track."
        case .missingFormat: "Video format information is missing."
        case .codec: "This video codec is not supported for frame saving."
        case .invalidTiming: "Could not read this video's frame timestamps."
        case .tooManyFrames: "Too many frames in this short interval."
        case .entryFrameMissing: "Could not locate the displayed frame. Try another position."
        case .hdrRequiresNewerOS: "HDR frame saving requires iOS 18 or later."
        case .colorProfile: "The frame's color profile is unavailable."
        case .colorConversion: "Could not convert this frame's colors."
        case .readFailed: "Could not read video frames. Try again."
        case .imageFailed: "Could not decode this frame. Try again."
        case .imageEncoding: "Could not create the JPEG photo."
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

/// Display only. Frame selection and filenames always retain original rational PTS.
enum FrameRelativeTime {
    static func text(_ time: CMTime, origin: CMTime) -> String {
        let value = max(0, CMTimeSubtract(time, origin).seconds)
        let milliseconds = Int((value * 1000).rounded())
        let seconds = milliseconds / 1000
        let base = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return milliseconds % 1000 == 0 ? base : base + String(format: ".%03d", milliseconds % 1000)
    }
}
