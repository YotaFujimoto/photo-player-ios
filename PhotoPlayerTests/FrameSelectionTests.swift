import XCTest
import CoreMedia
@testable import PhotoPlayer

final class FrameSelectionTests: XCTestCase {
    func testSamplingCountsAndUniformIndices() {
        let expected: [(Int, [Int])] = [
            (1,[0]),(9,Array(0..<9)),(10,Array(0..<10)),(18,Array(0..<10)),
            (90,(0..<10).map { $0 * 9 }), (91,(0..<10).map { $0 * 10 })
        ]
        for (count, indices) in expected {
            let state = FrameSelection(times: (0..<count).map { CMTime(value: Int64($0), timescale: 30) })
            XCTAssertEqual(state.indices, indices)
            XCTAssertEqual(Set(state.indices).count, indices.count)
        }
    }
    func testPositionOutsideRangeNeverMovesEndpointsOrWindow() {
        let times = (0...90).map { CMTime(value: Int64($0 + 150), timescale: 30) }
        XCTAssertEqual(try FrameSelection.window(times,entry:5),times)
        XCTAssertThrowsError(try FrameSelection.window(times,entry:4)) {
            XCTAssertEqual($0 as? FrameExportError,.unsupported,"Missing preceding timing cannot shift entry to a later frame")
        }
        var state = FrameSelection(times: times)
        state.show(30); state.setStart()
        state.show(60); state.setEnd()
        for index in [0,90,15,75,45] {
            state.show(index)
            XCTAssertEqual(state.start,30); XCTAssertEqual(state.end,60); XCTAssertEqual(state.times,times)
        }
        state.show(90); XCTAssertFalse(state.canSetStart); state.setStart(); XCTAssertEqual(state.start,30)
        state.show(0); XCTAssertFalse(state.canSetEnd); state.setEnd(); XCTAssertEqual(state.end,60)
        state.setStart(); XCTAssertEqual(state.start,0)
        state.setEnd(); XCTAssertEqual(state.indices,[0]); XCTAssertEqual(state.summary,"1 frame")
        state.show(90); state.setEnd(); XCTAssertEqual(state.end,90)
    }
    func testActualRationalIntervalNotRoundedLabelDrivesSampling() {
        let times = (0...90).map { CMTime(value: Int64($0 * 1001), timescale: 30_000) }
        let state = FrameSelection(times: times)
        XCTAssertEqual(state.indices,(0..<10).map { $0 * 10 })
        XCTAssertEqual(state.summary,"0.334 s · 10")
        XCTAssertEqual(state.times[state.indices[1]], CMTime(value: 10010, timescale: 30000))
        XCTAssertEqual(state.nearest(to: 2.99),90)
    }
    func testNamesGroupOrderUniquenessAndWindowsSafety() {
        let stem = FrameFileName.stem(original: "bad<>:\"/\\|?*名前.mov", identifier: "synthetic-id")
        XCTAssertEqual(stem,"bad名前")
        XCTAssertEqual(FrameFileName.stem(original: "CON.mov", identifier: "test"),"Video-CON")
        XCTAssertEqual(FrameFileName.stem(original: "CON.part.mov", identifier: "test"),"Video-CON.part")
        let fallback = FrameFileName.stem(original: nil, identifier: "same")
        XCTAssertEqual(fallback,FrameFileName.stem(original: nil, identifier: "same"))
        let id=UUID()
        let times=(0..<10).map { CMTime(value: Int64(150+$0*9), timescale: 30) }
        let names=times.enumerated().map { FrameFileName.make(stem:stem,start:times[0],operation:id,ordinal:$0.offset+1,actual:$0.element) }
        XCTAssertEqual(names,names.sorted()); XCTAssertEqual(Set(names).count,10)
        XCTAssertTrue(names[0].contains("__01__t-00-00-05-000.jpg"))
        XCTAssertNotEqual(names[0],FrameFileName.make(stem:stem,start:times[0],operation:UUID(),ordinal:1,actual:times[0]))
        let long=FrameFileName.stem(original:String(repeating:"あ",count:200)+".mov",identifier:"test")
        XCTAssertLessThanOrEqual(long.utf8.count,70)
    }
}
