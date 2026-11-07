@preconcurrency import Photos
@preconcurrency import PhotosUI
import SwiftUI

struct LibraryVideo: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
    var duration: String { PlaybackPolicy.clock(asset.duration) }
}

@MainActor
final class VideoLibrary: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var videos: [LibraryVideo] = []
    @Published private(set) var revision = 0
    let thumbnails = PHCachingImageManager()

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    var canRead: Bool { authorization == .authorized || authorization == .limited }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refresh()
    }

    func refresh() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        thumbnails.stopCachingImagesForAllAssets()
        guard canRead else { videos = []; revision += 1; return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var current: [LibraryVideo] = []
        current.reserveCapacity(result.count)
        for index in 0..<result.count { current.append(LibraryVideo(asset: result.object(at: index))) }
        videos = current
        revision += 1
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func changeLimitedSelection() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { @Sendable [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

// PhotoKit hands immutable images across its callback queue; ownership moves to MainActor.
private struct ThumbnailResult: @unchecked Sendable {
    let image: UIImage?
    let inCloud: Bool
}

@MainActor
final class ThumbnailModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var inCloud = false
    private var requestID: PHImageRequestID?
    private var gate = RequestGate()
    private var manager: PHCachingImageManager?
    private var asset: PHAsset?
    private let size = CGSize(width: 320, height: 240)
    private let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return options
    }()

    func start(asset: PHAsset, manager: PHCachingImageManager) {
        stop()
        self.asset = asset
        self.manager = manager
        let token = gate.begin()
        manager.startCachingImages(for: [asset], targetSize: size, contentMode: .aspectFill, options: options)
        requestID = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) {
            @Sendable [weak self] image, info in
            let result = ThumbnailResult(image: image, inCloud: info?[PHImageResultIsInCloudKey] as? Bool == true)
            Task { @MainActor in
                guard let self, self.gate.accepts(token) else { return }
                if let image = result.image { self.image = image }
                self.inCloud = result.inCloud
            }
        }
    }

    func stop() {
        gate.cancel()
        if let requestID { manager?.cancelImageRequest(requestID) }
        if let asset { manager?.stopCachingImages(for: [asset], targetSize: size, contentMode: .aspectFill, options: options) }
        requestID = nil
        asset = nil
        manager = nil
        image = nil
        inCloud = false
    }
}

struct VideoThumbnail: View {
    let video: LibraryVideo
    let manager: PHCachingImageManager
    let revision: Int
    @StateObject private var model = ThumbnailModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(.quaternary)
            if let image = model.image {
                Image(uiImage: image).resizable().scaledToFill()
                    .accessibilityIdentifier("videoThumbnail")
            } else {
                Image(systemName: model.inCloud ? "icloud" : "video")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
            Text(video.duration).font(.caption.monospacedDigit())
                .padding(4).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white).padding(6)
        }
        .frame(height: 110).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { model.start(asset: video.asset, manager: manager) }
        .onChange(of: revision) { _, _ in model.start(asset: video.asset, manager: manager) }
        .onDisappear { model.stop() }
    }
}
