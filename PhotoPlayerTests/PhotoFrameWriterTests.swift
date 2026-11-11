import XCTest
import Photos
import AVFoundation
import ImageIO
@testable import PhotoPlayer

final class PhotoFrameWriterTests: XCTestCase {
    @MainActor func testRealPhotoKitBatchPreservesNamesPixelsAndExistingAssets() async throws {
        XCTAssertEqual(PhotoFrameWriter.failure(for: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.notEnoughSpace.rawValue)), .storage)
        XCTAssertEqual(PhotoFrameWriter.failure(for: NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.accessUserDenied.rawValue)), .permission)
        XCTAssertEqual(PhotoFrameWriter.failure(for: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)), .storage)
        for sample in ["frames-30","frames-hlg","frames-pq","frames-variable","frames-30-crop","frames-hlg-crop-one"] {
        let fixture=sample.components(separatedBy:"-crop")[0]
        let crop=sample.contains("crop") ? FrameCrop(rect:CGRect(x:0,y:0,width:1,height:0.5)) : .full
        let before = PHAsset.fetchAssets(with: .image, options: nil)
        let existing = (0..<before.count).map { before.object(at:$0).localIdentifier }
        let source=FrameSource(input:FrameAsset(asset:try FrameSourceTests.asset(fixture),entry:.zero,flags:.init(),fileStem:"synthetic"))
        let times=try await source.catalogue()
        let indices=sample.hasSuffix("one") ? [21] : FrameSelection(times:times).indices
        let operation=UUID(), folder=try FrameWorkspace.create(id:UUID())
        defer { FrameWorkspace.remove(folder) }
        var photos: [PreparedPhoto]=[]
        for (offset,index) in indices.enumerated() {
            let name=FrameFileName.make(stem:"synthetic",start:times[0],operation:operation,ordinal:offset+1,actual:times[index])
            let url=folder.appendingPathComponent(name)
            _=try await source.writeJPEG(at:times[index],crop:crop,to:url)
            photos.append(PreparedPhoto(url:url,filename:name))
        }
        let writer=PhotoFrameWriter()
        try await writer.authorize()
        try await writer.save(photos)
        let after=PHAsset.fetchAssets(with:.image,options:nil)
        XCTAssertEqual(after.count,before.count+indices.count)
        let retained=PHAsset.fetchAssets(withLocalIdentifiers:existing,options:nil)
        XCTAssertEqual(retained.count,existing.count)
        var found=Set<String>()
        for index in 0..<after.count {
            let asset=after.object(at:index)
            let resource = try XCTUnwrap(PHAssetResource.assetResources(for:asset).first { $0.type == .photo })
            let name=resource.originalFilename
            guard let ordinal=photos.firstIndex(where: { $0.filename == name }) else { continue }
            XCTAssertTrue(found.insert(name).inserted)
            XCTAssertEqual(asset.pixelWidth,160); XCTAssertEqual(asset.pixelHeight,crop.isFull ? 96 : 48)
            // requestImageData(.current) can return a Photos-rendered rendition.
            // Validate the registered ORIGINAL resource's bytes/profile too.
            let restored = folder.appendingPathComponent("registered-\(ordinal).jpg")
            let resourceOptions = PHAssetResourceRequestOptions(); resourceOptions.isNetworkAccessAllowed = false
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: restored, options: resourceOptions) { @Sendable error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            let originalData = try Data(contentsOf: restored)
            XCTAssertEqual(originalData, try Data(contentsOf: photos[ordinal].url))
            XCTAssertNotNil(originalData.range(of: Data("ICC_PROFILE\0".utf8)), "Original Photos resource must retain its sRGB profile")
            let options=PHImageRequestOptions()
            options.version = .current; options.deliveryMode = .highQualityFormat; options.isNetworkAccessAllowed=false
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(for:asset,options:options) { @Sendable data,_,_,_ in
                    if let data { continuation.resume(returning:data) }
                    else { continuation.resume(throwing:FrameExportError.saveFailed) }
                }
            }
            let imageSource=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
            let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
            XCTAssertEqual(try FrameSourceTests.number(image),indices[ordinal])
        }
        XCTAssertEqual(found.count,indices.count)
        }
    }
}
