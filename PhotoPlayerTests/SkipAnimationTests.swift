import XCTest
import SwiftUI
import ImageIO
@testable import PhotoPlayer

final class SkipAnimationTests: XCTestCase {
    @MainActor func testStandardSymbolProbe() async throws {
        guard #available(iOS 18, *) else { throw XCTSkip("Rotate requires iOS 18") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = StandardSymbolProbeState()
        let host = UIHostingController(rootView: StandardSymbolProbe(state: state))
        host.safeAreaRegions = []; window.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { window.isHidden = true; previous?.makeKey() }
        _ = capture(host.view, afterScreenUpdates: true)
        let before = pixels(capture(host.view)); state.pulse += 1
        var frames: [(Double, UIImage, [UInt8])] = []
        let start = Date()
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(45))
            let shot = capture(host.view); let bytes = pixels(shot)
            print("CI_SF_PARTIAL centralDifference=\(meanDifference(core(before), core(bytes)))")
            frames.append((Date().timeIntervalSince(start), shot, bytes))
        }
        try attachMovie(frames, name: "official-goforward10-byLayer-probe")
        for name in ["arrow.clockwise", "arrow.counterclockwise"] {
            XCTAssertNotNil(UIImage(systemName: name)); print("CI_SF_AVAILABLE \(name)")
        }
    }
    @MainActor func testLiveArrowMovesInBothDirectionsWhileNumeralStaysFixed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = SkipAnimationState()
        let host = UIHostingController(rootView: SkipAnimationHarness(state: state))
        // This is a small capture canvas, not a full-screen phone controller.
        // Device safe-area insets otherwise displace the rendered ring center.
        host.safeAreaRegions = []
        window.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        defer { state.feedback = nil; window.isHidden = true; previous?.makeKey() }
        // Warm the real timeline/rendering view before starting the measured pulse.
        _ = capture(host.view, afterScreenUpdates: true)
        try await Task.sleep(for: .milliseconds(80))
        for (pulse, forward) in [true, false, true].enumerated() {
            // Replace an existing pulse, including a reversal, without removing
            // the view or awaiting a previous animation's completion.
            state.feedback = SkipFeedback(forward: forward, origin: 10, target: 20, duration: 30)
            let start = try XCTUnwrap(state.feedback).presentedAt
            var frames: [(Double, UIImage, [UInt8])] = []
            for _ in 0..<(pulse < 2 ? 3 : 8) {
                try await Task.sleep(for: .milliseconds(45))
                let shot = capture(host.view)
                frames.append((Date().timeIntervalSince(start), shot, pixels(shot)))
            }
            let first = try XCTUnwrap(frames.first)
            XCTAssertGreaterThan(core(first.2).reduce(0, +), 1000, "The fixed 10 must actually be visible")
            for frame in frames.dropFirst() {
                XCTAssertLessThan(meanDifference(core(first.2), core(frame.2)), 1,
                                  "The numeral must not rotate or translate with the arrow")
            }
            let pairs = zip(frames, frames.dropFirst()).filter { $0.1.0 < 0.40 && $0.1.0 - $0.0.0 < 0.17 }
            let shifts = pairs.map { angularShift(profile($0.0.2), profile($0.1.2)) }
            XCTAssertTrue(shifts.contains { forward ? $0 > 5 : $0 < -5 },
                          "Actual rendered frames must move in the requested direction: \(shifts)")
            XCTAssertFalse(shifts.contains { forward ? $0 < -5 : $0 > 5 }, "No reversed/queued turn: \(shifts)")
            print("CI_SKIP_MOTION forward=\(forward) times=\(frames.map { $0.0 }) shifts=\(shifts)")
            try attachMovie(frames, name: forward ? "arrow-clockwise" : "arrow-counterclockwise")
        }
        // Reverse again while Reduce Motion is on: actual rendered arrow and
        // numeral must both remain still, not just the model's angle value.
        state.reduced = true
        state.feedback = SkipFeedback(forward: false, origin: 20, target: 10, duration: 30)
        try await Task.sleep(for: .milliseconds(60))
        let reduced = pixels(capture(host.view))
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertLessThan(meanDifference(reduced, pixels(capture(host.view))), 1)
        state.feedback = nil
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertLessThan(pixels(capture(host.view)).map(Int.init).reduce(0, +), 100, "Removal leaves no timeline drawing")
    }

    @MainActor private func capture(_ view: UIView, afterScreenUpdates: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        format.preferredRange = .standard; format.opaque = true
        return UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            // Capture the latest committed screen without blocking for another
            // screen update. The previous synchronous capture took 150–190ms,
            // undersampling a 420ms turn; the task yields between real frames.
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: afterScreenUpdates))
        }
    }
    private func pixels(_ image: UIImage) -> [UInt8] {
        let cg = image.cgImage!, data = cg.dataProvider!.data!
        XCTAssertEqual(cg.bitsPerPixel, 32)
        let bytes = CFDataGetBytePtr(data)!
        // Renderer rows are top-down. A middle byte is a color component for
        // either 32-bit byte order; this white-on-black capture has equal RGB.
        return (0..<120).flatMap { y in (0..<120).map { x in bytes[y*cg.bytesPerRow + x*4 + 1] } }
    }
    private func core(_ pixels: [UInt8]) -> [Int] {
        (38..<82).flatMap { y in (38..<82).compactMap { x in
            hypot(Double(x-60), Double(y-60)) < 22 ? Int(pixels[y*120+x]) : nil
        } }
    }
    private func meanDifference<T: BinaryInteger>(_ a: [T], _ b: [T]) -> Double {
        Double(zip(a,b).reduce(0) { $0 + abs(Int($1.0)-Int($1.1)) }) / Double(a.count)
    }
    private func profile(_ pixels: [UInt8]) -> [Double] {
        (0..<360).map { degree in
            let angle = Double(degree) * .pi / 180
            return [40.0, 43.0, 46.0].reduce(0) { sum, radius in
                let x = Int((60 + radius * cos(angle)).rounded())
                let y = Int((60 + radius * sin(angle)).rounded())
                return sum + Double(pixels[y*120+x])
            }
        }
    }
    private func angularShift(_ a: [Double], _ b: [Double]) -> Int {
        (-160...160).min { left, right in
            func error(_ shift: Int) -> Double {
                (0..<360).reduce(0) { $0 + abs(a[$1] - b[($1 + shift + 360) % 360]) }
            }
            return error(left) < error(right)
        }!
    }
    private func attachMovie(_ frames: [(Double, UIImage, [UInt8])], name: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frames.count, nil))
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (index, frame) in frames.enumerated() {
            let delay = index + 1 < frames.count ? frames[index+1].0 - frame.0 : 0.25
            CGImageDestinationAddImage(output, frame.1.cgImage!,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let movie = XCTAttachment(contentsOfFile: url); movie.name = name; movie.lifetime = .keepAlways; add(movie)
        for index in [0, 1, 2] {
            let still = XCTAttachment(image: frames[index].1)
            still.name = "\(name)-t\(String(format: "%.3f", frames[index].0))"
            still.lifetime = .keepAlways; add(still)
        }
    }
}

@MainActor private final class StandardSymbolProbeState: ObservableObject { @Published var pulse = 0 }
@available(iOS 18, *) private struct StandardSymbolProbe: View {
    @ObservedObject var state: StandardSymbolProbeState
    var body: some View {
        ZStack {
            Color.black
            Image(systemName: "goforward.10").font(.system(size: 80))
                .symbolEffect(.rotate.byLayer, options: .speed(3), value: state.pulse)
        }.foregroundStyle(.white).frame(width: 120, height: 120)
    }
}

@MainActor private final class SkipAnimationState: ObservableObject {
    @Published var feedback: SkipFeedback? = SkipFeedback(forward: true, origin: 0, target: 10, duration: 30)
    @Published var reduced = false
}
private struct SkipAnimationHarness: View {
    @ObservedObject var state: SkipAnimationState
    var body: some View {
        ZStack {
            Color.black
            if let feedback = state.feedback {
                AnimatedSkipSymbol(feedback: feedback, reduceMotion: state.reduced).frame(width: 96, height: 96)
            }
        }.frame(width: 120, height: 120).foregroundStyle(.white).ignoresSafeArea()
    }
}
