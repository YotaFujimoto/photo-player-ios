import Foundation

enum SeekInteractionPolicy {
    static let horizontalSeekSecondsPerWidth = 60.0
    static let horizontalStartDistance = 12.0
    static let horizontalDominance = 1.5
    static let feedbackDuration = Duration.seconds(1)

    enum Direction { case pending, horizontal, rejected }

    static func direction(x: Double, y: Double) -> Direction {
        guard x.isFinite, y.isFinite else { return .rejected }
        let horizontal = abs(x), vertical = abs(y)
        if horizontal >= horizontalStartDistance && horizontal >= vertical * horizontalDominance { return .horizontal }
        if vertical >= horizontalStartDistance && vertical >= horizontal { return .rejected }
        return .pending
    }

    static func barPosition(x: Double, width: Double, duration: Double) -> Double {
        guard x.isFinite, width.isFinite, width > 0 else { return 0 }
        return PlaybackPolicy.position(min(max(x / width, 0), 1) * duration, duration: duration)
    }

    static func horizontalPosition(origin: Double, translation: Double, width: Double, duration: Double) -> Double {
        guard translation.isFinite, width.isFinite, width > 0 else { return PlaybackPolicy.position(origin, duration: duration) }
        return PlaybackPolicy.position(origin + translation / width * horizontalSeekSecondsPerWidth, duration: duration)
    }

    static func difference(_ delta: Double) -> String {
        guard delta.isFinite, abs(delta) >= 0.05 else { return "0s" }
        let magnitude = abs(delta)
        let number = abs(magnitude - magnitude.rounded()) < 0.05
            ? String(format: "%.0f", magnitude) : String(format: "%.1f", magnitude)
        return "\(delta > 0 ? "+" : "−")\(number)s"
    }
}

struct SeekPreview: Equatable {
    enum Source { case bar, horizontal }
    let source: Source
    let origin: Double
    var target: Double
    var difference: String { SeekInteractionPolicy.difference(target - origin) }
}

struct SkipFeedback: Equatable, Identifiable {
    let id = UUID()
    let forward: Bool
    let origin: Double
    let target: Double
    let duration: Double
    var text: String {
        let delta = target - origin
        let boundary = target <= 0 ? "Start" : target >= duration ? "End" : nil
        if abs(delta) < 0.05 { return boundary ?? "0s" }
        let difference = SeekInteractionPolicy.difference(delta)
        return boundary.map { "\(difference) · \($0)" } ?? difference
    }
}
