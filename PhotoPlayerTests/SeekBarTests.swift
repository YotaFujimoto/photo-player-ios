import XCTest
import UIKit
@testable import PhotoPlayer

final class SeekBarTests: XCTestCase {
    @MainActor private func makeBar() -> SeekBarControl {
        let bar = SeekBarControl(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        bar.configure(position: 10, duration: 30, enabled: true, cancellationID: 0)
        bar.layoutIfNeeded()
        bar.onBegin = { true }
        return bar
    }

    @MainActor func testTapAndContinuousDragCommitExactlyOnceWithLargeHitArea() {
        let bar = makeBar()
        var targets: [Double] = [], commits = 0
        bar.onChange = { targets.append($0) }; bar.onCommit = { commits += 1 }
        XCTAssertTrue(bar.point(inside: CGPoint(x: 150, y: 1), with: nil))
        XCTAssertTrue(bar.point(inside: CGPoint(x: 150, y: 43), with: nil))
        XCTAssertTrue(bar.start(at: 75)); bar.finish(at: 75); bar.finish(at: 75)
        XCTAssertEqual(targets.last, 7.5)
        XCTAssertEqual(commits, 1)
        XCTAssertTrue(bar.start(at: 50))
        for x in 50...250 { bar.move(to: CGFloat(x)) }
        XCTAssertEqual(commits, 1, "Moves only update the preview")
        bar.finish(at: 250)
        XCTAssertEqual(targets.last, 25)
        XCTAssertEqual(commits, 2)
        XCTAssertTrue(bar.start(at: -10)); bar.finish(at: -10)
        XCTAssertEqual(targets.last, 0)
        XCTAssertTrue(bar.start(at: 310)); bar.finish(at: 310)
        XCTAssertEqual(targets.last, 30)
    }

    @MainActor func testCancellationResizeAndInvalidationNeverCommitLateRelease() {
        let bar = makeBar()
        var commits = 0, cancellations = 0
        bar.onCommit = { commits += 1 }; bar.onCancel = { cancellations += 1 }
        XCTAssertTrue(bar.start(at: 100)); bar.cancelInteraction(); bar.finish(at: 200)
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(bar.start(at: 100)); bar.frame.size.width = 500; bar.layoutIfNeeded(); bar.finish(at: 400)
        XCTAssertEqual(cancellations, 2)
        XCTAssertTrue(bar.start(at: 100))
        bar.configure(position: 10, duration: 30, enabled: true, cancellationID: 1)
        bar.finish(at: 400)
        XCTAssertEqual(cancellations, 3)
        XCTAssertTrue(bar.start(at: 100)); SeekBar.dismantleUIView(bar, coordinator: ()); bar.finish(at: 400)
        XCTAssertEqual(cancellations, 4)
        XCTAssertEqual(commits, 0)
    }

    @MainActor func testDisabledRejectedAndAccessibleAdjustment() {
        let bar = makeBar()
        var commits = 0
        bar.onCommit = { commits += 1 }
        bar.onBegin = { false }
        XCTAssertFalse(bar.start(at: 100)); bar.finish(at: 200)
        XCTAssertEqual(commits, 0)
        bar.onBegin = { true }
        bar.accessibilityIncrement()
        XCTAssertEqual(bar.accessibilityValue, "0:15 of 0:30")
        bar.accessibilityDecrement()
        XCTAssertEqual(bar.accessibilityValue, "0:10 of 0:30")
        XCTAssertEqual(commits, 2)
        bar.configure(position: 10, duration: 30, enabled: false, cancellationID: 0)
        XCTAssertFalse(bar.start(at: 100)); bar.accessibilityIncrement()
        XCTAssertEqual(commits, 2)
    }
}
