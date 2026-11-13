import XCTest
import SwiftUI
@testable import PhotoPlayer

final class LongDurationLayoutTests: XCTestCase {
    @MainActor private func bar(in view: UIView) -> SeekBarControl? {
        if let value = view as? SeekBarControl { return value }
        return view.subviews.lazy.compactMap { self.bar(in: $0) }.first
    }

    @MainActor private func awaitRender(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "The mounted SwiftUI content must render before measuring it")
    }

    @MainActor private func window(for host: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    @MainActor func testLegacyVariableClockResizesAndCancelsActiveContact() async throws {
        // Preserve the former composition only in this regression. This proves
        // the layout/cancel mechanism, not the cause of every device symptom.
        var cancelled = 0, committed = 0
        let actions = PlaybackTransportActions(begin: { true }, commit: { committed += 1 }, cancel: { cancelled += 1 })
        var rendered: Double?
        func content(_ position: Double) -> some View {
            LegacyClockRow(position: position, actions: actions).frame(width: 390, height: 100)
                .background(ClockRenderReceipt(position: position) { rendered = $0 })
        }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: content(0))
        let window = try window(for: host)
        defer { window.isHidden = true; previous?.makeKey() }
        try await awaitRender { rendered == 0 && self.bar(in: host.view) != nil }
        host.view.layoutIfNeeded()
        let control = try XCTUnwrap(bar(in: host.view))
        let before = control.bounds.width
        XCTAssertTrue(control.start(at: before * 0.99))
        host.rootView = content(7128)
        try await awaitRender { rendered == 7128 }
        host.view.setNeedsLayout(); host.view.layoutIfNeeded(); control.layoutIfNeeded()
        XCTAssertTrue(bar(in: host.view) === control)
        XCTAssertNotEqual(control.bounds.width, before)
        XCTAssertFalse(control.interacting)
        XCTAssertEqual(cancelled, 1)
        control.finish(at: before * 0.99); XCTAssertEqual(committed, 0)
        print("Legacy long clock width \(before) -> \(control.bounds.width); tracking cancelled before commit")
    }

    @MainActor func testProductionClockKeepsTrackAndContactAcrossAllTimeDigits() async throws {
        for width in [320.0, 390, 780] {
            for duration in [15.0, 3599, 3600, 3601, 7200] {
                var target = 0.0, committed = 0, cancelled = 0
                let actions = PlaybackTransportActions(begin: { true }, change: { target = $0 },
                    commit: { committed += 1 }, cancel: { cancelled += 1 })
                var rendered: Double?
                func content(_ position: Double) -> some View {
                    PlaybackTransportControls(state: PlaybackTransportState(position: position, duration: duration, isReady: true), actions: actions)
                        .frame(width: width, height: 110)
                        .background(ClockRenderReceipt(position: position) { rendered = $0 })
                }
                let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
                let host = UIHostingController(rootView: content(0))
                let window = try window(for: host)
                defer { window.isHidden = true; previous?.makeKey() }
                try await awaitRender { rendered == 0 && self.bar(in: host.view) != nil }
                host.view.layoutIfNeeded()
                let control = try XCTUnwrap(bar(in: host.view))
                let rect = control.convert(control.bounds, to: host.view)
                XCTAssertGreaterThan(rect.width, 100); XCTAssertEqual(rect.height, 44)
                for fraction in [0.0, 0.01, 0.19, 0.81, 0.99, 1, 0.01] {
                    let x = control.bounds.width * fraction
                    XCTAssertTrue(control.point(inside: CGPoint(x: min(x, control.bounds.width - 0.01), y: 1), with: nil))
                    XCTAssertTrue(control.start(at: x))
                    host.rootView = content(target)
                    try await awaitRender { rendered == target }
                    host.view.setNeedsLayout(); host.view.layoutIfNeeded(); control.layoutIfNeeded()
                    XCTAssertTrue(bar(in: host.view) === control)
                    XCTAssertEqual(control.convert(control.bounds, to: host.view), rect)
                    XCTAssertTrue(control.interacting, "Clock changes must not cancel a contact")
                    control.move(to: x); control.finish(at: x)
                    XCTAssertEqual(target, duration * fraction, accuracy: 0.000001)
                }
                XCTAssertEqual(committed, 7); XCTAssertEqual(cancelled, 0)
            }
        }
    }
}

/// A render receipt, not a timing assumption. It never handles input.
private struct ClockRenderReceipt: UIViewRepresentable {
    let position: Double
    let received: (Double) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false; return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { received(position) }
}

private struct LegacyClockRow: View {
    let position: Double
    let actions: PlaybackTransportActions
    var body: some View {
        HStack(spacing: 8) {
            Text(PlaybackPolicy.clock(position))
            SeekBar(position: position, duration: 7200, enabled: true, cancellationID: 0,
                    onBegin: actions.begin, onChange: actions.change, onCommit: actions.commit, onCancel: actions.cancel).frame(height: 44)
            Text(PlaybackPolicy.clock(7200))
        }.font(.caption.monospacedDigit()).lineLimit(1).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 2)
    }
}
