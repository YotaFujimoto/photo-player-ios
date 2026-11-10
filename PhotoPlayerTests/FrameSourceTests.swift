import XCTest
import AVFoundation
import ImageIO
@testable import PhotoPlayer

final class FrameSourceTests: XCTestCase {
    // Synthetic fixture probe only: compare compressed reader timing and
    // attachments against ffprobe before changing any frame-boundary rule.
    static func probe(_ asset: AVAsset) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let range = try await track.load(.timeRange)
        print("Synthetic track time range", range)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: 325, timescale: 100))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output); XCTAssertTrue(reader.startReading()); defer { reader.cancelReading() }
        for _ in 0..<8 {
            guard let sample = output.copyNextSampleBuffer() else { break }
            var timing = CMSampleTimingInfo()
            CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
            print("Synthetic sample", CMSampleBufferGetPresentationTimeStamp(sample), "output", CMSampleBufferGetOutputPresentationTimeStamp(sample), timing,
                  CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as Any)
        }
    }
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
        for name in ["frames-30", "frames-reordered", "frames-hevc"] {
        let source=FrameSource(input:FrameAsset(asset:try Self.asset(name),entry:CMTime(value:21,timescale:30),flags:.init(),fileStem:"synthetic"))
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
    }
    func testFractionalRateAndEndWindowUseExistingFrames() async throws {
        let asset=try Self.asset("frames-2997")
        let source=FrameSource(input:FrameAsset(asset:asset,entry:CMTime(value:21*1001,timescale:30000),flags:.init(),fileStem:"synthetic"))
        let times=try await source.catalogue()
        XCTAssertEqual(times.count,90)
        for index in FrameSelection(times:times).indices {
            let result=try await source.image(at:times[index])
            XCTAssertEqual(try Self.number(result.image),21+index)
        }
        let end=try await asset.load(.duration)
        let tail=FrameSource(input:FrameAsset(asset:asset,entry:end,flags:.init(),fileStem:"synthetic"))
        let last=try await tail.catalogue()
        XCTAssertEqual(last.count,1); XCTAssertLessThan(last[0].seconds,end.seconds)
        let result=try await tail.image(at:last[0])
        XCTAssertEqual(try Self.number(result.image),150)
    }
    func testRotationPreservesOrientedResolutionAndAspect() async throws {
        let source=FrameSource(input:FrameAsset(asset:try Self.asset("frames-rotated"),entry:.zero,flags:.init(),fileStem:"synthetic"))
        let times=try await source.catalogue()
        let image=try await source.image(at:times[30],fullSize:true)
        XCTAssertEqual(image.image.width,96); XCTAssertEqual(image.image.height,160)
    }
    func testAdjustedCaptureReasonsAreDistinctAndAnonymous() async throws {
        let cases: [(FrameInputFlags,FrameExportError)] = [
            (.init(adjustmentData:true),.adjusted),(.init(adjustmentBaseVideo:true),.adjusted),
            (.init(highFrameRate:true),.highFrameRateCapture),(.init(timelapse:true),.timelapse),
            (.init(videoComposition:true),.videoComposition)
        ]
        for (flags,reason) in cases {
            let source=FrameSource(input:FrameAsset(asset:try Self.asset("frames-30"),entry:.zero,flags:flags,fileStem:"private-name"))
            do { _=try await source.catalogue(); XCTFail("Unsupported adjustments accepted") }
            catch { XCTAssertEqual(error as? FrameExportError,reason) }
            let report=await source.diagnosticReport()
            XCTAssertTrue(report.contains("reason=\(reason.rawValue)")); XCTAssertTrue(report.contains("nominalFPS="))
            XCTAssertFalse(report.contains("private-name")); XCTAssertFalse(report.contains("frames-30")); XCTAssertFalse(report.contains("file:"))
        }
    }
    func testVariableFramesUseMeasuredTimesAndUniquePixelNumbers() async throws {
        for name in ["frames-variable","frames-hlg-variable"] {
            let source=FrameSource(input:FrameAsset(asset:try Self.asset(name),entry:.zero,fileStem:"synthetic"))
            let times=try await source.catalogue()
            XCTAssertTrue(FrameTiming.isVariable(times)); XCTAssertTrue(FrameSelection(times:times).summary.hasPrefix("≈"))
            XCTAssertGreaterThan(times.count,50); XCTAssertLessThan(times.count,91)
            var numbers=Set<Int>()
            let folder=try FrameWorkspace.create(id:UUID()); defer { FrameWorkspace.remove(folder) }
            for index in FrameSelection(times:times).indices {
                let preview=try await source.image(at:times[index])
                XCTAssertEqual(try Self.number(preview.image),index)
                let url=folder.appendingPathComponent("\(index).jpg")
                let actual=try await source.writeJPEG(at:times[index],to:url)
                XCTAssertEqual(CMTimeCompare(actual,times[index]),0)
                let decoded=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil))
                let jpeg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded,0,nil))
                let number=try Self.number(jpeg)
                XCTAssertEqual(number,index); XCTAssertTrue(numbers.insert(number).inserted)
            }
            // Consecutive frame steps across the cadence change, not 1/30 adds.
            for index in 43...47 {
                let frame=try await source.image(at:times[index])
                XCTAssertEqual(try Self.number(frame.image),index)
            }
            let report=await source.diagnosticReport()
            XCTAssertTrue(report.contains("cadence=variable")); XCTAssertTrue(report.contains("metadataWindowSeconds="))
        }
    }
    func testRounded2997TimestampsKeepActualFrameIdentity() async throws {
        let source=FrameSource(input:FrameAsset(asset:try Self.asset("frames-rounded"),entry:.zero,fileStem:"synthetic"))
        let times=try await source.catalogue()
        XCTAssertFalse(FrameTiming.isVariable(times)); XCTAssertGreaterThan(times.count,89)
        XCTAssertGreaterThan(Set(FrameTiming.intervals(times).map { Int(($0 * 600).rounded()) }).count,1)
        for index in [0,1,25,49,50,75,89] {
            let frame=try await source.image(at:times[index])
            XCTAssertEqual(try Self.number(frame.image),index)
        }
    }
    func testReadFailureIsNotReportedAsHDRorFrameRateRejection() async throws {
        let missing=AVURLAsset(url:FileManager.default.temporaryDirectory.appendingPathComponent("private-missing-video.mov"))
        let source=FrameSource(input:FrameAsset(asset:missing,entry:.zero,fileStem:"private-name"))
        do { _=try await source.catalogue(); XCTFail("Missing input accepted") }
        catch { XCTAssertEqual(error as? FrameExportError,.readFailed) }
        let report=await source.diagnosticReport()
        XCTAssertTrue(report.contains("reason=readFailed")); XCTAssertFalse(report.contains("private-")); XCTAssertFalse(report.contains("file:"))
    }
}
