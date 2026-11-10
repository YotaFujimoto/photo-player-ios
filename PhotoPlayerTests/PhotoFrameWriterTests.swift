import XCTest
import Photos
import AVFoundation
import ImageIO
@testable import PhotoPlayer

final class PhotoFrameWriterTests: XCTestCase {
    @MainActor func testRealPhotoKitBatchPreservesNamesPixelsAndExistingAssets() async throws {
        let before = PHAsset.fetchAssets(with: .image, options: nil)
        let existing = (0..<before.count).map { before.object(at:$0).localIdentifier }
        let source=FrameSource(input:FrameAsset(asset:try FrameSourceTests.asset("frames-30"),entry:.zero,disallowed:false,fileStem:"synthetic"))
        let times=try await source.catalogue()
        let indices=FrameSelection(times:times).indices
        let operation=UUID(), folder=try FrameWorkspace.create(id:UUID())
        defer { FrameWorkspace.remove(folder) }
        var photos: [PreparedPhoto]=[]
        for (offset,index) in indices.enumerated() {
            let name=FrameFileName.make(stem:"synthetic",start:times[0],operation:operation,ordinal:offset+1,actual:times[index])
            let url=folder.appendingPathComponent(name)
            _=try await source.writeJPEG(at:times[index],to:url)
            photos.append(PreparedPhoto(url:url,filename:name))
        }
        let writer=PhotoFrameWriter()
        try await writer.authorize()
        try await writer.save(photos)
        let after=PHAsset.fetchAssets(with:.image,options:nil)
        XCTAssertEqual(after.count,before.count+10)
        let retained=PHAsset.fetchAssets(withLocalIdentifiers:existing,options:nil)
        XCTAssertEqual(retained.count,existing.count)
        var found=Set<String>()
        for index in 0..<after.count {
            let asset=after.object(at:index)
            let name=PHAssetResource.assetResources(for:asset).first?.originalFilename ?? ""
            guard let ordinal=photos.firstIndex(where: { $0.filename == name }) else { continue }
            XCTAssertTrue(found.insert(name).inserted)
            XCTAssertEqual(asset.pixelWidth,160); XCTAssertEqual(asset.pixelHeight,96)
            let options=PHImageRequestOptions()
            options.version = .current; options.deliveryMode = .highQualityFormat; options.isNetworkAccessAllowed=false
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(for:asset,options:options) { data,_,_,_ in
                    if let data { continuation.resume(returning:data) }
                    else { continuation.resume(throwing:FrameExportError.saveFailed) }
                }
            }
            let imageSource=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
            let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
            XCTAssertEqual(try FrameSourceTests.number(image),indices[ordinal])
        }
        XCTAssertEqual(found.count,10)
    }
}
