import Foundation

enum PlaybackPolicy {
    static let rates: [Float] = [0.25, 0.5, 1, 1.25, 1.5, 2]

    static func skip(from seconds: Double, forward: Bool, duration: Double) -> Double {
        position(position(seconds, duration: duration) + (forward ? 10 : -10), duration: duration)
    }

    static func position(_ seconds: Double, duration: Double) -> Double {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(seconds, 0), duration)
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let value = Int(min(seconds, 359_999))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
        }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func errorCode(_ error: Error?) -> String {
        guard let error else { return "Unknown" }
        let nsError = error as NSError
        let domain = nsError.domain.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0)
        }
        return "\(String(String.UnicodeScalarView(domain)).prefix(64)) / \(nsError.code)"
    }
}

/// The held rate never overwrites the user's chosen rate.
struct PlaybackSpeed {
    private(set) var selected: Float = 1
    private(set) var isBoosting = false
    var effective: Float { isBoosting ? 2 : selected }

    mutating func select(_ rate: Float) {
        guard PlaybackPolicy.rates.contains(rate) else { return }
        isBoosting = false
        selected = rate
    }

    mutating func beginHold(isPlaying: Bool) {
        guard isPlaying else { return }
        isBoosting = true
    }

    mutating func endHold() { isBoosting = false }
}

/// Invalidates progress and results from cancelled or superseded PhotoKit requests.
struct RequestGate {
    private(set) var token = UUID()
    private(set) var isActive = false

    mutating func begin() -> UUID {
        token = UUID()
        isActive = true
        return token
    }

    func accepts(_ candidate: UUID) -> Bool { isActive && candidate == token }

    mutating func finish(_ candidate: UUID) -> Bool {
        guard accepts(candidate) else { return false }
        isActive = false
        return true
    }

    mutating func cancel() {
        isActive = false
        token = UUID()
    }
}

struct SeekRequest: Equatable {
    let seconds: Double
    let exact: Bool
    var timescale: Int32 = 600
}

/// One in-flight seek; only the most recent pending position is retained.
struct SeekQueue {
    private(set) var active: SeekRequest?
    private var pending: SeekRequest?
    var isBusy: Bool { active != nil }

    mutating func enqueue(_ request: SeekRequest) -> SeekRequest? {
        if active != nil {
            pending = request
            return nil
        }
        active = request
        return request
    }

    mutating func finish() -> SeekRequest? {
        active = pending
        pending = nil
        return active
    }

    mutating func cancel() { active = nil; pending = nil }
}
