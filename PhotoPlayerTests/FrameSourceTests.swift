import XCTest
import AVFoundation
import ImageIO
@testable import PhotoPlayer

final class FrameSourceTests: XCTestCase {
    static func asset(_ name: String) throws -> AVURLAsset {
        let root = try XCTUnwrap(Bundle(for: FrameSourceTests.self).url(forResource: "frame-fixtures", withExtension: nil))
        let url = root.appendingPathComponent(name + ".mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        return AVURLAsset(url: url)
    }
    static func number(_ image: CGImage) throws -> Int {
        var pixels=[UInt8](repeating:0,count:image.width*image.height*4)
        let space=CGColorSpaceCreateDeviceRGB()
        try pixels.withUnsafeMutableBytes { buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        var value=0
        for bit in 0..<8 {
            let offset=((image.height*16/96)*image.width+(image.width*(bit*20+10)/160))*4
            if pixels[offset] > 127 { value |= 1 << bit }
        }
        return value
    }
    func testThirtyFPSActualPixelsPreviewAndJPEGMatchEveryChosenFrame() async throws {
        let source=FrameSource(input:FrameAsset(asset:try Self.asset("frames-30"),entry:CMTime(value:21,timescale:30),disallowed:false,fileStem:"synthetic"))
        let times=try await source.catalogue()
        XCTAssertEqual(times.count,91); XCTAssertEqual(times.first,CMTime(value:21,timescale:30))
        let state=FrameSelection(times:times)
        let folder=try FrameWorkspace.create(id:UUID())
        defer { FrameWorkspace.remove(folder) }
        for index in state.indices {
            let frame=try await source.image(at:times[index])
            XCTAssertEqual(try Self.number(frame.image),21+index)
            let url=folder.appendingPathComponent("\(index).jpg")
            let actual=try await source.writeJPEG(at:times[index],to:url)
            XCTAssertEqual(actual,times[index])
            let data=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil))
            let jpeg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(data,0,nil))
            XCTAssertEqual(jpeg.width,160); XCTAssertEqual(jpeg.height,96)
            XCTAssertEqual(try Self.number(jpeg),21+index)
        }
    }
    func testFractionalRateAndEndWindowUseExistingFrames() async throws {
        let asset=try Self.asset("frames-2997")
        let source=FrameSource(input:FrameAsset(asset:asset,entry:CMTime(value:21*1001,timescale:30000),disallowed:false,fileStem:"synthetic"))
        let times=try await source.catalogue()
        XCTAssertEqual(times.count,90)
        for index in FrameSelection(times:times).indices {
            let result=try await source.image(at:times[index])
            XCTAssertEqual(try Self.number(result.image),21+index)
        }
        let end=try await asset.load(.duration)
        let tail=FrameSource(input:FrameAsset(asset:asset,entry:end,disallowed:false,fileStem:"synthetic"))
        let last=try await tail.catalogue()
        XCTAssertEqual(last.count,1); XCTAssertLessThan(last[0].seconds,end.seconds)
        let result=try await tail.image(at:last[0])
        XCTAssertEqual(try Self.number(result.image),150)
    }
    func testRotationPreservesOrientedResolutionAndAspect() async throws {
        let source=FrameSource(input:FrameAsset(asset:try Self.asset("frames-rotated"),entry:.zero,disallowed:false,fileStem:"synthetic"))
        let times=try await source.catalogue()
        let image=try await source.image(at:times[30],fullSize:true)
        XCTAssertEqual(image.image.width,96); XCTAssertEqual(image.image.height,160)
    }
    func testVariableTimingAndEditedInputAreExplicitlyRejected() async throws {
        for (name,disallowed) in [("frames-variable",false),("frames-30",true)] {
            let source=FrameSource(input:FrameAsset(asset:try Self.asset(name),entry:.zero,disallowed:disallowed,fileStem:"synthetic"))
            do { _=try await source.catalogue(); XCTFail("Unsupported input accepted") }
            catch { XCTAssertEqual(error as? FrameExportError,.unsupported) }
        }
    }
}
