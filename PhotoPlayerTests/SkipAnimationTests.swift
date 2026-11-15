import XCTest
import SwiftUI
@testable import PhotoPlayer

/// simctl records the real screen without synchronous captures interrupting a
/// 280ms turn. check-skip-recording.py gates direction, fixed numeral and cleanup.
final class SkipAnimationTests: XCTestCase {
    @MainActor func testLiveArrowMovesInBothDirectionsWhileNumeralStaysFixed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = SkipAnimationState()
        let host = UIHostingController(rootView: SkipAnimationHarness(state: state))
        host.safeAreaRegions = []
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        defer { state.marker = .black; state.feedback = nil; window.isHidden = true; previous?.makeKey() }
        // Flush initial rendering before the measured pulses, never during them.
        _ = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        print("CI_SKIP_CANVAS \(Int(window.bounds.width)) \(Int(window.bounds.height))")
        for (forward, color, duration) in [(true, Color(red: 0, green: 1, blue: 0), 450), (false, Color(red: 0, green: 1, blue: 1), 180), (true, Color(red: 1, green: 0, blue: 1), 500)] {
            state.feedback = SkipFeedback(forward: forward, origin: 10, target: 20, duration: 30)
            state.marker = color
            // Observation windows only; the product's turn stays at 0.28s.
            // Reverse/replace an existing pulse without waiting out its display.
            try await Task.sleep(for: .milliseconds(duration))
        }
        state.reduced = true
        state.feedback = SkipFeedback(forward: false, origin: 20, target: 10, duration: 30)
        state.marker = Color(red: 1, green: 1, blue: 0)
        try await Task.sleep(for: .milliseconds(400))
        state.feedback = nil; state.marker = Color(red: 0, green: 0, blue: 1)
        try await Task.sleep(for: .milliseconds(200))
        state.marker = .black
        _ = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
    }
}

@MainActor private final class SkipAnimationState: ObservableObject {
    @Published var feedback: SkipFeedback? = SkipFeedback(forward: true, origin: 0, target: 10, duration: 30)
    @Published var reduced = false
    @Published var marker = Color.black
}
private struct SkipAnimationHarness: View {
    @ObservedObject var state: SkipAnimationState
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let feedback = state.feedback {
                AnimatedSkipSymbol(feedback: feedback, reduceMotion: state.reduced)
                    .frame(width: 96, height: 96).position(x: 100, y: 240)
            }
            Rectangle().fill(state.marker).frame(width: 32, height: 20).position(x: 36, y: 130)
        }.foregroundStyle(.white).ignoresSafeArea()
    }
}
