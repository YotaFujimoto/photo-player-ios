import XCTest
import CoreMedia
import CoreGraphics
@testable import PhotoPlayer

actor StubFrameSource: FrameProviding {
    let times = (0...90).map { CMTime(value: Int64($0), timescale: 30) }
    var holdsImages = false
    var holdsWrites = false
    var imageCalls: [Int] = []
    var written: [URL] = []
    var writtenCrops: [FrameCrop] = []
    private var imageWaiter: CheckedContinuation<Void, Never>?
    private var writeWaiter: CheckedContinuation<Void, Never>?
    func configure(images: Bool = false, writes: Bool = false) { holdsImages = images; holdsWrites = writes }
    var waitingImage: Bool { imageWaiter != nil }
    var waitingWrite: Bool { writeWaiter != nil }
    func releaseImage() { imageWaiter?.resume(); imageWaiter = nil }
    func releaseWrite() { writeWaiter?.resume(); writeWaiter = nil }
    func catalogue() async throws -> [CMTime] { times }
    func image(at time: CMTime, fullSize: Bool) async throws -> FrameImage {
        imageCalls.append(Int((time.seconds * 30).rounded()))
        if holdsImages { await withCheckedContinuation { imageWaiter = $0 } }
        let context = CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,
                                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        return FrameImage(image:context.makeImage()!,time:time)
    }
    func writeJPEG(at time: CMTime, to url: URL) async throws -> CMTime {
        written.append(url)
        if holdsWrites { await withCheckedContinuation { writeWaiter = $0 } }
        try Task.checkCancellation()
        try Data([1,2,3]).write(to:url)
        return time
    }
    func writeJPEG(at time: CMTime, crop: FrameCrop, to url: URL) async throws -> CMTime {
        writtenCrops.append(crop)
        return try await writeJPEG(at: time, to: url)
    }
    func cancel() async {}
}

@MainActor final class StubFrameWriter: FramePhotoWriting {
    var failure: FrameExportError?
    var denied = false
    var holdsSave = false
    var batches: [[PreparedPhoto]] = []
    private var completion: CheckedContinuation<Void, Never>?
    func authorize() async throws { if denied { throw FrameExportError.permission } }
    func save(_ photos: [PreparedPhoto]) async throws {
        batches.append(photos)
        if holdsSave { await withCheckedContinuation { completion = $0 } }
        if let failure { throw failure }
    }
    func complete() { completion?.resume(); completion = nil }
}

final class FrameExtractionModelTests: XCTestCase {
    @MainActor func testCropPersistsAcrossFramesAndResetDoesNotMoveEndpoints() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        let model=try await ready(source,writer)
        defer { model.close() }
        model.request(index:30); try await wait { model.canSetEndpoints }; model.setStart()
        let video=CGRect(x:0,y:0,width:400,height:300)
        model.toggleCrop(); XCTAssertTrue(model.isCropping); XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.beginInteraction(),"Crop cannot start a time swipe")
        XCTAssertTrue(model.beginCrop(at:.zero,video:video))
        model.moveCrop(CGPoint(x:80,y:60)); model.finishCrop()
        let crop=model.crop
        XCTAssertEqual(crop.rect,CGRect(x:0.2,y:0.2,width:0.8,height:0.8))
        XCTAssertTrue(model.isCropping,"Releasing a drag does not exit")
        model.toggleCrop(); model.toggleCrop()
        XCTAssertEqual(model.crop,crop); XCTAssertEqual(model.selection?.position,30)
        XCTAssertEqual(model.selection?.start,30); XCTAssertEqual(model.selection?.end,90)
        model.step(forward:true); try await wait { !model.isPreviewing }
        XCTAssertEqual(model.selection?.position,31); XCTAssertEqual(model.selection?.start,30)
        XCTAssertEqual(model.selection?.end,90); XCTAssertEqual(model.crop,crop); XCTAssertTrue(model.isCropping)
        model.toggleCrop(); model.resetCrop()
        XCTAssertEqual(model.crop,.full); XCTAssertEqual(model.selection?.position,31); XCTAssertEqual(model.selection?.start,30)
        model.toggleCrop(); XCTAssertTrue(model.beginCrop(at:.zero,video:video)); model.moveCrop(CGPoint(x:70,y:50))
        model.backgrounded()
        XCTAssertEqual(model.crop,.full); XCTAssertFalse(model.isCropping); XCTAssertFalse(model.isInteracting)
    }
    @MainActor func testDoneFreezesOneCropForAllFramesAndCancelRestoresDragOrigin() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        let model=try await ready(source,writer)
        defer { model.close() }
        let video=CGRect(x:0,y:0,width:400,height:300)
        model.toggleCrop(); XCTAssertTrue(model.beginCrop(at:.zero,video:video))
        model.moveCrop(CGPoint(x:100,y:60)); model.finishCrop()
        let crop=model.crop
        XCTAssertTrue(model.beginCrop(at:CGPoint(x:250,y:180),video:video))
        model.moveCrop(CGPoint(x:-30,y:-30)); model.cancelGestures()
        XCTAssertEqual(model.crop,crop); XCTAssertTrue(model.isCropping)
        model.toggleCrop(); await source.configure(writes:true)
        model.save(); try await wait { await source.waitingWrite }
        model.resetCrop(); model.toggleCrop(); model.request(index:70); model.save()
        XCTAssertEqual(model.crop,crop); XCTAssertFalse(model.isCropping); XCTAssertEqual(model.selection?.position,0)
        await source.configure(writes:false); await source.releaseWrite()
        try await wait { model.phase == .saved }
        let crops=await source.writtenCrops
        XCTAssertEqual(crops,Array(repeating:crop,count:10)); XCTAssertEqual(writer.batches.count,1)
        XCTAssertEqual(model.savedCount,10)
        XCTAssertTrue(writer.batches[0].allSatisfy { !FileManager.default.fileExists(atPath:$0.url.path) })
    }
    @MainActor private func wait(_ predicate: () async -> Bool) async throws {
        let deadline=ContinuousClock.now.advanced(by:.seconds(5))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { XCTFail("Condition timed out"); return }
            try await Task.sleep(for:.milliseconds(10))
        }
    }
    @MainActor private func ready(_ source: StubFrameSource, _ writer: StubFrameWriter) async throws -> FrameExtractionModel {
        let model=FrameExtractionModel(source:source,fileStem:"synthetic",writer:writer)
        model.prepare()
        try await wait { model.canSave }
        return model
    }
    @MainActor func testOnlyLatestDecodedFrameCanSetEndpoints() async throws {
        let source=StubFrameSource(); await source.configure(images:true)
        let model=FrameExtractionModel(source:source,fileStem:"synthetic",writer:StubFrameWriter())
        defer { model.close() }
        model.prepare()
        try await wait { await source.waitingImage }
        model.request(index:10); model.request(index:20); model.setStart()
        XCTAssertFalse(model.canSetEndpoints); XCTAssertEqual(model.selection?.start,0)
        await source.releaseImage()
        try await wait {
            let calls = await source.imageCalls
            let waiting = await source.waitingImage
            return calls == [0,20] && waiting
        }
        XCTAssertNil(model.preview); XCTAssertEqual(model.selection?.position,0)
        await source.releaseImage()
        try await wait { model.canSetEndpoints }
        XCTAssertEqual(model.selection?.position,20)
        model.setStart(); XCTAssertEqual(model.selection?.start,20)
    }
    @MainActor func testSaveFreezesBatchBlocksDoubleTapAndWaitsForRegistration() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        writer.holdsSave=true
        let model=try await ready(source,writer)
        defer { model.close() }
        model.save(); model.save(); model.request(index:40); model.setStart()
        try await wait { model.phase == .saving }
        model.toggleCrop(); model.resetCrop(); model.save()
        XCTAssertFalse(model.isCropping); XCTAssertFalse(model.canSave)
        XCTAssertEqual(writer.batches.count,1); XCTAssertEqual(writer.batches[0].count,10)
        XCTAssertEqual(model.selection?.position,0); XCTAssertEqual(model.selection?.start,0)
        let files=writer.batches[0].map(\.url)
        XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath:$0.path) })
        XCTAssertFalse(model.canClose); model.close(); XCTAssertEqual(model.phase,.saving)
        model.backgrounded(); XCTAssertEqual(model.phase,.saving)
        XCTAssertEqual(model.savedCount,0)
        writer.complete()
        try await wait { model.phase == .saved }
        XCTAssertEqual(model.savedCount,10)
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath:$0.path) })
        model.save(); XCTAssertEqual(writer.batches.count,1)
    }
    @MainActor func testCancelPreparationNeverRegistersAndRemovesTemporaryFiles() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        let model=try await ready(source,writer)
        await source.configure(writes:true)
        model.save()
        try await wait { await source.waitingWrite }
        let files=await source.written
        model.close(); await source.releaseWrite()
        try await wait { !FileManager.default.fileExists(atPath:files[0].deletingLastPathComponent().path) }
        XCTAssertTrue(writer.batches.isEmpty); XCTAssertEqual(model.savedCount,0)
    }
    @MainActor func testBackgroundStopsPreparationWithoutLosingRange() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        let model=try await ready(source,writer)
        defer { model.close() }
        model.request(index:30); try await wait { model.canSetEndpoints }; model.setStart()
        await source.configure(writes:true)
        model.save(); try await wait { await source.waitingWrite }
        model.backgrounded(); await source.releaseWrite()
        try await wait { model.phase == .ready }
        XCTAssertEqual(model.selection?.start,30); XCTAssertEqual(model.selection?.end,90)
        XCTAssertTrue(writer.batches.isEmpty)
    }
    @MainActor func testSaveFailurePreservesSelectionAndRemovesFiles() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        writer.failure = .storage
        let model=try await ready(source,writer)
        defer { model.close() }
        model.request(index:30); try await wait { model.canSetEndpoints }; model.setStart()
        model.save(); try await wait { model.phase == .ready }
        XCTAssertEqual(model.selection?.start,30); XCTAssertEqual(model.selection?.end,90)
        XCTAssertEqual(model.error,FrameExportError.storage.localizedDescription)
        XCTAssertEqual(writer.batches.count,1)
        XCTAssertTrue(writer.batches[0].allSatisfy { !FileManager.default.fileExists(atPath:$0.url.path) })
    }
    @MainActor func testUnknownResultNeverRetriesOrClaimsCancellation() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        writer.failure = .uncertain
        let model=try await ready(source,writer)
        defer { model.close() }
        model.save(); try await wait { model.phase == .uncertain }
        XCTAssertEqual(model.savedCount,0); XCTAssertFalse(model.canSave)
        model.save(); XCTAssertEqual(writer.batches.count,1)
    }
    @MainActor func testDeniedPermissionDoesNotGenerateOrRegisterPhotos() async throws {
        let source=StubFrameSource(), writer=StubFrameWriter()
        writer.denied=true
        let model=try await ready(source,writer)
        defer { model.close() }
        model.save(); try await wait { model.phase == .ready }
        XCTAssertEqual(model.error,FrameExportError.permission.localizedDescription)
        let writes=await source.written
        XCTAssertTrue(writes.isEmpty); XCTAssertTrue(writer.batches.isEmpty)
    }
}
