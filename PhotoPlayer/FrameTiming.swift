import CoreMedia
import Foundation

/// Classification affects the label, never whether measured frames may be used.
enum FrameTiming {
    /// Compressed media PTS and output/display PTS can differ because of the
    /// container's timeline mapping, even without a Photos user adjustment.
    static func outputTimes(_ sample: CMSampleBuffer) throws -> [CMTime] {
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0 else { return [] }
        guard count <= 4096 else { throw FrameExportError.tooManyFrames }
        var needed = 0
        guard CMSampleBufferGetOutputSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &needed) == noErr,
              needed == 1 || needed == count else { throw FrameExportError.invalidTiming }
        var timing = Array(repeating: CMSampleTimingInfo(), count: needed)
        let status = timing.withUnsafeMutableBufferPointer {
            CMSampleBufferGetOutputSampleTimingInfoArray(sample, entryCount: needed, arrayToFill: $0.baseAddress, entriesNeededOut: nil)
        }
        guard status == noErr else { throw FrameExportError.invalidTiming }
        return try (0..<count).map { index in
            let item = timing[needed == 1 ? 0 : index]
            var time = item.presentationTimeStamp
            if needed == 1 && index > 0 {
                guard item.duration.isNumeric, item.duration.seconds > 0 else { throw FrameExportError.invalidTiming }
                time = CMTimeAdd(time, CMTimeMultiply(item.duration, multiplier: Int32(index)))
            }
            guard time.isNumeric else { throw FrameExportError.invalidTiming }
            return time
        }
    }
    static func precision(_ times: [CMTime]) -> Double {
        times.filter { $0.timescale > 0 }.map { 1 / Double($0.timescale) }.max() ?? 0
    }
    static func intervals(_ times: [CMTime]) -> [Double] {
        zip(times.dropFirst(), times).map { CMTimeSubtract($0, $1).seconds }
    }
    static func isVariable(_ times: [CMTime]) -> Bool {
        guard times.count > 2 else { return false }
        let span = CMTimeSubtract(times.last!, times[0]).seconds
        let mean = span / Double(times.count - 1)
        // A quantized constant cadence can alternate timestamp increments.
        // Compare the entire measured grid, with at most one source tick of
        // uncertainty (capped at 2 ms), not floating-point equality or fps=30.
        let tolerance = max(0.000002, min(0.002, precision(times)))
        return times.indices.contains {
            abs(CMTimeSubtract(times[$0], times[0]).seconds - Double($0) * mean) > tolerance
        }
    }
    static func uniqueSorted(_ times: [CMTime]) -> [CMTime] {
        var result: [CMTime] = []
        for time in times.sorted(by: { CMTimeCompare($0, $1) < 0 }) {
            if result.last.map({ CMTimeCompare($0, time) != 0 }) ?? true { result.append(time) }
        }
        return result
    }
    static func matches(actual: CMTime, index: Int, times: [CMTime]) -> Bool {
        guard actual.isNumeric, times.indices.contains(index) else { return false }
        let expected = times[index]
        if CMTimeCompare(actual, expected) == 0 { return true }
        let closest = times.indices.min { abs(CMTimeSubtract(times[$0], actual).seconds) < abs(CMTimeSubtract(times[$1], actual).seconds) }
        guard closest == index else { return false }
        var gaps: [Double] = []
        if index > 0 { gaps.append(CMTimeSubtract(expected, times[index - 1]).seconds) }
        if index + 1 < times.count { gaps.append(CMTimeSubtract(times[index + 1], expected).seconds) }
        // Allow representation rounding only inside this frame's identity.
        let tolerance = min(precision([actual, expected]), (gaps.min() ?? 0.004) / 4)
        return abs(CMTimeSubtract(actual, expected).seconds) <= tolerance
    }
    static func report(_ times: [CMTime]) -> String {
        let gaps = intervals(times)
        let mean = gaps.isEmpty ? 0 : gaps.reduce(0,+) / Double(gaps.count)
        let values = gaps.prefix(12).map { String(format: "%.6f", $0) }.joined(separator: ",")
        return String(format: "frames=%d cadence=%@ tick=%.9fs delta[min/mean/max]=%.6f/%.6f/%.6fs measuredFPS=%.4f firstDeltas=[%@]", times.count,
                      isVariable(times) ? "variable" : "uniform-within-precision", precision(times), gaps.min() ?? 0, mean, gaps.max() ?? 0,
                      mean > 0 ? 1 / mean : 0, values)
    }
}
