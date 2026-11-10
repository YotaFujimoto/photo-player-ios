import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoPlayer

final class FrameJPEGTests: XCTestCase {
    private func decoded(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    func testEmbeddedConversionProfilePreservesPixelsAndNeverDuplicates() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = try XCTUnwrap(context.makeImage())
        let original = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let profile = try XCTUnwrap(space.copyICCData()) as Data
        let encoded = try FrameJPEG.embed(profile: profile, in: original as Data)
        XCTAssertNotNil(encoded.range(of: Data("ICC_PROFILE\0".utf8)))
        XCTAssertEqual(try FrameJPEG.embed(profile: profile, in: encoded), encoded)
        let before = try decoded(original as Data), after = try decoded(encoded)
        XCTAssertEqual(before.width, after.width); XCTAssertEqual(before.height, after.height)
        XCTAssertEqual(before.dataProvider?.data as Data?, after.dataProvider?.data as Data?)
        XCTAssertEqual(after.colorSpace?.copyICCData() as Data?, profile)
        let saved = try FrameJPEG.encode(image)
        XCTAssertEqual(try decoded(saved).colorSpace?.copyICCData() as Data?, profile)
    }
    func testProfileChunkingAndMalformedJPEGRejection() throws {
        // Minimal marker structure for container-only testing; not image data.
        let header = Data([0xff,0xd8,0xff,0xe0,0,4,1,2,0xff,0xda,0,2,3,4,0xff,0xd9])
        let profile = Data((0..<70000).map { UInt8($0 % 251) })
        let output = try FrameJPEG.embed(profile: profile, in: header)
        XCTAssertEqual(output.prefix(8), header.prefix(8)) // APP0 retained first.
        var offset = 8, reconstructed = Data()
        for sequence in 1...2 {
            XCTAssertEqual(output[offset + 1], 0xe2)
            let size = Int(output[offset + 2]) * 256 + Int(output[offset + 3])
            XCTAssertEqual(output[offset + 16], UInt8(sequence)); XCTAssertEqual(output[offset + 17], 2)
            reconstructed.append(output.subdata(in: (offset + 18)..<(offset + size + 2)))
            offset += size + 2
        }
        XCTAssertEqual(reconstructed, profile)
        XCTAssertEqual(output.suffix(from: offset), header.suffix(from: 8))
        for bad in [Data(), Data([0xff,0xd8,0xff,0xe0,0xff,0xff]), Data([0xff,0xd8,0xff,0xe0,0,1])] {
            XCTAssertThrowsError(try FrameJPEG.embed(profile: profile, in: bad))
        }
    }
}
