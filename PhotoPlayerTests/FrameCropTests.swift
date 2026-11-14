import XCTest
import SwiftUI
import CoreMedia
import ImageIO
@testable import PhotoPlayer

private final class CropStateFixture: CropGestureRecognizer {
    private var suppliedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State { get { suppliedState } set { suppliedState = newValue } }
}

final class FrameCropTests: XCTestCase {
    @MainActor func testPortraitMarginExpandsOnlyTapFamilyAndKeepsLandscapePictureBoundary() throws {
        let view = FramePreviewView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 96)).image { _ in UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 160, height: 96)) }
        let recognizers = try XCTUnwrap(view.gestureRecognizers)
        XCTAssertEqual(recognizers.count, 5, "No parent/window recognizers or new drag surface")
        for cropping in [false, true] {
            view.cropping = cropping
            for allowsMargins in [false, true] {
                view.allowsMarginTap = allowsMargins
                for recognizer in recognizers {
                    let tapFamily = recognizer is UITapGestureRecognizer || recognizer is UILongPressGestureRecognizer
                    for point in [CGPoint(x: 195, y: 180), CGPoint(x: 195, y: 660)] {
                        XCTAssertFalse(view.videoRect.insetBy(dx: -22, dy: -22).contains(point))
                        XCTAssertEqual(view.accepts(recognizer, at: point), allowsMargins && tapFamily)
                    }
                    XCTAssertTrue(view.accepts(recognizer, at: CGPoint(x: 195, y: 422)))
                    XCTAssertFalse(view.accepts(recognizer, at: CGPoint(x: -50, y: -50)))
                }
            }
        }
        view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        view.allowsMarginTap = false
        for recognizer in recognizers { XCTAssertFalse(view.accepts(recognizer, at: CGPoint(x: 20, y: 195))) }
    }

    func testAspectFitAndFeedbackStayInsideTallWideSquareImagesAcrossRotation() {
        for canvas in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            for image in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080), CGSize(width: 1000, height: 1000)] {
                let bounds = CGRect(origin: .zero, size: canvas)
                let video = VideoGeometry.fitted(image, in: bounds)
                XCTAssertEqual(video.width / video.height, image.width / image.height, accuracy: 0.00001)
                XCTAssertEqual(video.midX, bounds.midX); XCTAssertEqual(video.midY, bounds.midY)
                XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(video))
                for forward in [false, true] {
                    let label = SeekFeedbackStyle.skipFrame(in: video, forward: forward)
                    XCTAssertTrue(video.contains(label))
                    XCTAssertLessThan(label.width, 80)
                }
                let crop = FrameCrop(rect: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4))
                let display = crop.displayed(in: video)
                XCTAssertEqual((display.minX - video.minX) / video.width, 0.2, accuracy: 0.00001)
                XCTAssertEqual((display.minY - video.minY) / video.height, 0.3, accuracy: 0.00001)
                XCTAssertEqual(crop.pixels(width: 1000, height: 2000), CGRect(x: 200, y: 600, width: 600, height: 800))
            }
        }
        XCTAssertEqual(SeekFeedbackStyle.fontSize, 16)
    }
    func testCornersEdgesAndInteriorLatchWithoutJumpAndClamp() throws {
        let video = CGRect(x: 30, y: 100, width: 400, height: 300)
        let start = FrameCrop(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let r = start.displayed(in: video)
        let locations = [CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.maxX,y:r.minY), CGPoint(x:r.minX,y:r.maxY), CGPoint(x:r.maxX,y:r.maxY),
                         CGPoint(x:r.minX,y:r.midY), CGPoint(x:r.maxX,y:r.midY), CGPoint(x:r.midX,y:r.minY), CGPoint(x:r.midX,y:r.maxY),
                         CGPoint(x:r.midX,y:r.midY)]
        for point in locations {
            let drag = try XCTUnwrap(CropDrag(crop: start, video: video, point: point))
            XCTAssertEqual(drag.applying(.zero), start, "A contact never snaps the edge to the finger")
            for delta in [CGPoint(x: 999, y: 999), CGPoint(x: -999, y: -999), CGPoint(x: 20, y: -10)] {
                let result = drag.applying(delta).rect
                XCTAssertGreaterThanOrEqual(result.minX, 0); XCTAssertGreaterThanOrEqual(result.minY, 0)
                XCTAssertLessThanOrEqual(result.maxX, 1.000001); XCTAssertLessThanOrEqual(result.maxY, 1.000001)
                XCTAssertGreaterThanOrEqual(result.width, 0.14999); XCTAssertGreaterThanOrEqual(result.height, 0.19999)
            }
        }
        let edge = try XCTUnwrap(CropDrag(crop:start, video:video, point:CGPoint(x:r.minX + 5,y:r.midY)))
        XCTAssertEqual(edge.target, .edge(left: true, right: false, top: false, bottom: false))
        let moved = edge.applying(CGPoint(x:20,y:70)).rect
        XCTAssertEqual(moved.minX, 0.25, accuracy:0.00001); XCTAssertEqual(moved.minY, start.rect.minY)
        XCTAssertEqual(moved.maxY, start.rect.maxY)
        let move = try XCTUnwrap(CropDrag(crop:start,video:video,point:CGPoint(x:r.midX,y:r.midY)))
        XCTAssertEqual(move.target,.move); XCTAssertEqual(move.applying(CGPoint(x:999,y:999)).rect.size,start.rect.size)
    }
    func testFullAndPartialPixelCropKeepsOrientationDimensionsICCAndNoUpscale() throws {
        // Four colored quadrants plus a numbered pixel grid, supplied as top-left rows.
        let w = 120, h = 80
        var bytes = [UInt8](repeating:0,count:w*h*4)
        for y in 0..<h { for x in 0..<w {
            let i = (y*w+x)*4
            bytes[i] = x < w/2 ? 200 : 20
            bytes[i+1] = y < h/2 ? 180 : 30
            bytes[i+2] = UInt8((x + y) % 128); bytes[i+3] = 255
        } }
        let provider = try XCTUnwrap(CGDataProvider(data:Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        XCTAssertTrue(try FrameCrop.full.apply(to:image) === image)
        let crop = FrameCrop(rect:CGRect(x:0.5,y:0,width:0.5,height:0.5))
        let output = try crop.apply(to:image)
        XCTAssertEqual(output.width,60); XCTAssertEqual(output.height,40)
        let sampled = pixels(output)
        // Data rows and CGImage.cropping share top-left image coordinates.
        for (x,y) in [(5,5),(50,5),(5,30),(50,30)] {
            let i=(y*60+x)*4, original=(y*w+(x+60))*4
            XCTAssertEqual(Array(sampled[i..<i+3]),Array(bytes[original..<original+3]))
        }
        let data = try FrameJPEG.encode(output)
        XCTAssertNotNil(data.range(of:Data("ICC_PROFILE".utf8)))
        let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
        let jpeg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(jpeg.width,60); XCTAssertEqual(jpeg.height,40)
        let decoded=pixels(jpeg)
        for i in [5*60*4+5*4,30*60*4+50*4] { for c in 0..<3 { XCTAssertLessThan(abs(Int(decoded[i+c])-Int(sampled[i+c])),8) } }
        let attachment=XCTAttachment(image:UIImage(cgImage:jpeg)); attachment.name="top-right-crop-grid-sRGB"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func pixels(_ image:CGImage) -> [UInt8] {
        var data=[UInt8](repeating:0,count:image.width*image.height*4)
        data.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,
                                  space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return data
    }
    @MainActor func testRenderedCropCanvasKeepsColoredCornersAndGeometryAcrossAspectRatios() throws {
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        let crop=FrameCrop(rect:CGRect(x:0.25,y:0.25,width:0.5,height:0.5))
        for size in [CGSize(width:160,height:96),CGSize(width:96,height:160),CGSize(width:120,height:120)] {
            let original=UIGraphicsImageRenderer(size:size,format:format).image { _ in
                for (color,rect) in [(UIColor.red,CGRect(x:0,y:0,width:size.width/2,height:size.height/2)),
                                     (.green,CGRect(x:size.width/2,y:0,width:size.width/2,height:size.height/2)),
                                     (.blue,CGRect(x:0,y:size.height/2,width:size.width/2,height:size.height/2)),
                                     (.yellow,CGRect(x:size.width/2,y:size.height/2,width:size.width/2,height:size.height/2))] {
                    color.setFill(); UIRectFill(rect)
                }
            }
            let view=FramePreviewView(frame:.zero); view.image=original; view.crop=crop
            for canvas in [CGSize(width:320,height:600),CGSize(width:600,height:320)] {
                view.frame=CGRect(origin:.zero,size:canvas); view.layoutIfNeeded()
                let before=view.frame
                view.cropping=true; view.layoutIfNeeded()
                XCTAssertEqual(view.frame,before); XCTAssertEqual(view.crop,crop)
                let rendered=UIGraphicsImageRenderer(size:canvas,format:format).image { context in view.layer.render(in:context.cgContext) }
                let image=try XCTUnwrap(rendered.cgImage), data=pixels(image)
                // Independently locate the four colored interiors in the centered fitted image.
                let factor=min(canvas.width/size.width,canvas.height/size.height)
                for (nx,ny,color) in [(0.125,0.125,[255,0,0]),(0.875,0.125,[0,255,0]),(0.125,0.875,[0,0,255]),(0.875,0.875,[255,255,0])] {
                    let x=Int((canvas.width-size.width*factor)/2 + size.width*factor*nx)
                    let y=Int((canvas.height-size.height*factor)/2 + size.height*factor*ny)
                    let offset=(y*image.width+x)*4
                    for c in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(data[offset+c])-color[c]),2) }
                }
                view.cropping=false; view.layoutIfNeeded()
                XCTAssertEqual(view.frame,before); XCTAssertEqual(view.crop,crop)
                let attachment=XCTAttachment(image:rendered)
                attachment.name="crop-canvas-\(Int(size.width))x\(Int(size.height))-\(Int(canvas.width))"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
    func testRelativeTimeUsesFixedOriginAndDoesNotModifyRationalTimes() {
        let origin=CMTime(value: 300300, timescale:30000)
        XCTAssertEqual(FrameRelativeTime.text(origin,origin:origin),"0:00")
        XCTAssertEqual(FrameRelativeTime.text(CMTimeAdd(origin,CMTime(value:1001,timescale:30000)),origin:origin),"0:00.033")
        XCTAssertEqual(FrameRelativeTime.text(CMTimeAdd(origin,CMTime(value:3,timescale:1)),origin:origin),"0:03")
        XCTAssertEqual(origin.value,300300)
    }
    func testSystemEdgePriorityOnlyForActiveLandscapeCrop() {
        for landscape in [false,true] { for crop in [false,true] { for active in [false,true] {
            XCTAssertEqual(CropEdgePolicy.edges(landscape:landscape,cropping:crop,active:active),landscape && crop && active ? .all : [])
        } } }
    }
    @MainActor func testCropRecognizerRequiresMovementAndNeverStartsFromSmallJitter() {
        let recognizer=CropStateFixture()
        let view=UIView(); view.addGestureRecognizer(recognizer)
        recognizer.start(at:CGPoint(x:100,y:100)); recognizer.move(to:CGPoint(x:102,y:103))
        XCTAssertEqual(recognizer.state,.possible)
        recognizer.move(to:CGPoint(x:100,y:108)); XCTAssertEqual(recognizer.state,.began)
        XCTAssertEqual(recognizer.origin,CGPoint(x:100,y:100)); XCTAssertEqual(recognizer.translation,CGPoint(x:0,y:8))
    }
}
