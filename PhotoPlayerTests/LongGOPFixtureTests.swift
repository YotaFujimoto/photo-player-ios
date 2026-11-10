import XCTest
import Photos

/// Run only after CI imports the original encoding, following the 12-video suite.
final class LongGOPFixtureTests: XCTestCase {
    func testOriginalFixtureIsNewestPhotoKitVideo() throws {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let videos = PHAsset.fetchAssets(with: .video, options: options)
        XCTAssertEqual(videos.count, 13)
        let first = try XCTUnwrap(videos.firstObject)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-02-01T00:00:00Z"))
        XCTAssertEqual(try XCTUnwrap(first.creationDate).timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(first.pixelWidth, 320)
        XCTAssertEqual(first.pixelHeight, 180)
        XCTAssertEqual(first.duration, 30, accuracy: 0.1)
    }
}
