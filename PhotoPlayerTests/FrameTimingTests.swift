import XCTest
import CoreMedia
@testable import PhotoPlayer

final class FrameTimingTests: XCTestCase {
    func testContainerOutputTimestampIsUsedInsteadOfMediaTimestamp() throws {
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: 2, timescale: 30), decodeTimeStamp: .zero)
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: nil,
                                               sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                               sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample), noErr)
        let buffer = try XCTUnwrap(sample)
        XCTAssertEqual(CMSampleBufferSetOutputPresentationTimeStamp(buffer, newValue: .zero), noErr)
        XCTAssertEqual(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(buffer), timing.presentationTimeStamp), 0)
        XCTAssertEqual(try FrameTiming.outputTimes(buffer), [.zero])
    }
    func testRoundedCadenceAndTrueVariableIntervalsAreDifferent() {
        let rounded=(0...90).map { CMTime(value:Int64((Double($0)*1001/30000*600).rounded()),timescale:600) }
        XCTAssertFalse(FrameTiming.isVariable(rounded))
        XCTAssertFalse(FrameSelection(times:rounded).summary.hasPrefix("≈"))
        let variable: [CMTime] = (0...90).map { (index: Int) in
            let tick: Int = index < 45 ? index : 45 + (index - 45) * 2
            return CMTime(value: Int64(tick), timescale: 30)
        }
        var selection=FrameSelection(times:variable)
        XCTAssertTrue(FrameTiming.isVariable(variable)); XCTAssertTrue(selection.summary.hasPrefix("≈"))
        XCTAssertEqual(selection.indices,(0..<10).map { $0*10 })
        XCTAssertEqual(selection.summary,"≈0.500 s · 10")
        selection.show(20); selection.setStart(); selection.show(40); selection.setEnd()
        selection.show(90)
        XCTAssertEqual(selection.start,20); XCTAssertEqual(selection.end,40); XCTAssertEqual(selection.times,variable)
    }
    func testMatchingAllowsRepresentationRoundingButNeverAdjacentFrame() {
        let times=(0...90).map { CMTime(value:Int64($0*1001),timescale:30000) }
        let rounded=CMTimeConvertScale(times[51],timescale:600,method:.roundHalfAwayFromZero)
        XCTAssertTrue(FrameTiming.matches(actual:rounded,index:51,times:times))
        XCTAssertFalse(FrameTiming.matches(actual:times[50],index:51,times:times))
        XCTAssertFalse(FrameTiming.matches(actual:times[52],index:51,times:times))
        XCTAssertFalse(FrameTiming.matches(actual:.invalid,index:51,times:times))
        XCTAssertEqual(FrameTiming.uniqueSorted([times[1],times[0],CMTime(value:0,timescale:600),times[1]]),[times[0],times[1]])
    }
    @MainActor func testFrameReportsSurviveInputHistoryAndRemainBoundedInExistingCopy() {
        let trace=SelectionTrace()
        for index in 1...10 {
            let id=trace.beginFrameOperation(video:index)
            trace.recordFrameOperation(id,text:"nominalFPS=29.97 transfer=HLG cadence=variable")
        }
        for _ in 0..<110 { trace.inputNote("synthetic.input") }
        let report=trace.report
        XCTAssertFalse(report.contains("F1 V1\n")); XCTAssertTrue(report.contains("F3 V3\n"))
        XCTAssertTrue(report.contains("F10 V10\n")); XCTAssertTrue(report.contains("transfer=HLG"))
        XCTAssertTrue(report.contains("[events]")); XCTAssertTrue(report.contains("source=UIApplication.sendEvent"))
        trace.recordFrameOperation(1,text:"expired")
        XCTAssertFalse(trace.report.contains("expired"))
    }
}
