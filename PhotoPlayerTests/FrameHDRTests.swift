import XCTest
import AVFoundation
import ImageIO
import UIKit
@testable import PhotoPlayer

final class FrameHDRTests: XCTestCase {
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
                                              space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        let offset=(y*image.width+x)*4
        return bytes[offset..<offset+3].map(Int.init)
    }
    func testHLGAndPQProduceMatchingSDRProfilesGradientsColorsAndJPEGFrames() async throws {
        for name in ["frames-hlg","frames-pq"] {
            let source=FrameSource(input:FrameAsset(asset:try FrameSourceTests.asset(name),entry:.zero,fileStem:"synthetic"))
            let times=try await source.catalogue()
            let folder=try FrameWorkspace.create(id:UUID()); defer { FrameWorkspace.remove(folder) }
            do {
            for index in [0,21,60,90] {
                print("HDR check", name, index, "preview")
                let preview=try await source.image(at:times[index])
                XCTAssertEqual(try FrameSourceTests.number(preview.image),index)
                XCTAssertEqual(preview.image.colorSpace?.name.map { $0 as String },CGColorSpace.sRGB as String)
                XCTAssertEqual(preview.image.bitsPerComponent,8)
                let url=folder.appendingPathComponent("\(index).jpg")
                print("HDR check", name, index, "JPEG")
                let actual=try await source.writeJPEG(at:times[index],to:url)
                XCTAssertEqual(CMTimeCompare(actual,times[index]),0)
                let data=try Data(contentsOf:url)
                if index == 0 || index == 21 {
                    let file = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
                    file.name = "\(name)-\(index)-encoded-JPEG"; file.lifetime = .keepAlways; add(file)
                }
                print("HDR JPEG bytes", name, index, data.count)
                XCTAssertNotNil(data.range(of:Data("ICC_PROFILE".utf8)),"\(name) frame \(index): the JPEG must carry the actual profile, not only a label")
                let imageSource=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
                let jpeg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
                let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource,0,nil) as? [String:Any])
                let profile=try XCTUnwrap(properties[kCGImagePropertyProfileName as String] as? String)
                XCTAssertTrue(profile.lowercased().contains("srgb"),profile)
                XCTAssertEqual(try FrameSourceTests.number(jpeg),index)
                XCTAssertEqual(jpeg.width,160); XCTAssertEqual(jpeg.height,96)
                var ramp: [Int]=[]
                for column in 0..<8 {
                    let p=try pixel(preview.image,x:column*20+10,y:50)
                    let j=try pixel(jpeg,x:column*20+10,y:50)
                    XCTAssertLessThanOrEqual(p.max()!-p.min()!,4,"Neutral patches must not acquire a color cast")
                    for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(p[channel]-j[channel]),8) }
                    ramp.append(p[0])
                }
                XCTAssertLessThan(ramp[0],5); XCTAssertGreaterThan(ramp[2],ramp[0])
                XCTAssertGreaterThan(ramp[4],ramp[2]); XCTAssertGreaterThan(ramp[7],ramp[2]+40)
                for column in 1..<8 { XCTAssertGreaterThanOrEqual(ramp[column]+2,ramp[column-1]) }
                for channel in 0..<3 {
                    let color=try pixel(preview.image,x:channel*40+20,y:80)
                    for other in 0..<3 where other != channel { XCTAssertGreaterThan(color[channel],color[other]+30) }
                }
                if index == 21 {
                    let attachment=XCTAttachment(image:UIImage(cgImage:jpeg))
                    attachment.name="\(name)-SDR-sRGB-JPEG"; attachment.lifetime = .keepAlways; add(attachment)
                    print("\(name) neutral SDR levels=\(ramp) profile=\(profile)")
                }
            }
            } catch {
                print("HDR source failure", name, await source.diagnosticReport())
                throw error
            }
            let report=await source.diagnosticReport()
            XCTAssertTrue(report.contains(name == "frames-hlg" ? "transfer=HLG" : "transfer=PQ"))
            XCTAssertTrue(report.contains(name == "frames-pq" ? "CoreImage.toneMapHDRtoSDR" : "forceSDR")); XCTAssertTrue(report.contains("SDR-sRGB8"))
        }
    }
    func testHDRRotationUsesSameOrientedResolutionForPreviewAndSave() async throws {
        let source=FrameSource(input:FrameAsset(asset:try FrameSourceTests.asset("frames-hlg-rotated"),entry:.zero,fileStem:"synthetic"))
        let times=try await source.catalogue()
        let preview=try await source.image(at:times[21])
        let full=try await source.image(at:times[21],fullSize:true)
        XCTAssertEqual(preview.image.width,96); XCTAssertEqual(preview.image.height,160)
        XCTAssertEqual(full.image.width,96); XCTAssertEqual(full.image.height,160)
        let folder=try FrameWorkspace.create(id:UUID()); defer { FrameWorkspace.remove(folder) }
        let url=folder.appendingPathComponent("rotated.jpg")
        _=try await source.writeJPEG(at:times[21],to:url)
        let imageSource=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil))
        let jpeg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
        XCTAssertEqual(jpeg.width,96); XCTAssertEqual(jpeg.height,160)
        for point in [(16,10),(50,60),(80,100)] {
            let p=try pixel(preview.image,x:point.0,y:point.1), j=try pixel(jpeg,x:point.0,y:point.1)
            for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(p[channel]-j[channel]),8) }
        }
    }
}
