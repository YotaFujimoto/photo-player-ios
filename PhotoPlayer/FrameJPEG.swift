import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum FrameJPEG {
    static func encode(_ image: CGImage) throws -> Data {
        guard let profile = image.colorSpace?.copyICCData() as Data? else { throw FrameExportError.colorProfile }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw FrameExportError.imageEncoding }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FrameExportError.imageEncoding }
        // ImageIO may encode named sRGB using EXIF ColorSpace=1 without an ICC
        // payload. Embed the actual conversion profile for portable output.
        // This changes only APP2 metadata, never the compressed image samples.
        return try embed(profile: profile, in: data as Data)
    }

    static func embed(profile: Data, in jpeg: Data) throws -> Data {
        guard !profile.isEmpty, profile.count <= 65519 * 255 else { throw FrameExportError.colorProfile }
        guard jpeg.count > 4, jpeg[0] == 0xff, jpeg[1] == 0xd8 else { throw FrameExportError.imageEncoding }
        let signature = Data("ICC_PROFILE\0".utf8)
        var result = Data(jpeg.prefix(2)), offset = 2
        while offset + 4 <= jpeg.count {
            guard jpeg[offset] == 0xff else { throw FrameExportError.imageEncoding }
            let marker = jpeg[offset + 1]
            if marker == 0xda {
                let count = (profile.count + 65518) / 65519
                for index in 0..<count {
                    let lower = index * 65519, upper = min(profile.count, lower + 65519)
                    let size = upper - lower + 16 // length field + signature + sequence/count
                    result.append(contentsOf: [0xff, 0xe2, UInt8(size >> 8), UInt8(size & 0xff)])
                    result.append(signature)
                    result.append(contentsOf: [UInt8(index + 1), UInt8(count)])
                    result.append(profile.subdata(in: lower..<upper))
                }
                result.append(jpeg.subdata(in: offset..<jpeg.count))
                return result
            }
            let size = Int(jpeg[offset + 2]) * 256 + Int(jpeg[offset + 3])
            guard size >= 2, offset + 2 + size <= jpeg.count else { throw FrameExportError.imageEncoding }
            let payload = (offset + 4)..<(offset + 2 + size)
            let oldICC = marker == 0xe2 && jpeg.subdata(in: payload).starts(with: signature)
            if !oldICC { result.append(jpeg.subdata(in: offset..<(offset + 2 + size))) }
            offset += 2 + size
        }
        throw FrameExportError.imageEncoding
    }
}
