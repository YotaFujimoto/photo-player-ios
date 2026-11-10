@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// AVAsset is read-only; the actor owns its readers/generators. Never pass an AVPlayer.
struct FrameAsset: @unchecked Sendable {
    let asset: AVAsset
    let entry: CMTime
    let disallowed: Bool
    let fileStem: String
}
struct FrameImage: @unchecked Sendable {
    let image: CGImage
    let time: CMTime
}

protocol FrameProviding: Sendable {
    func catalogue() async throws -> [CMTime]
    func image(at time: CMTime, fullSize: Bool) async throws -> FrameImage
    func writeJPEG(at time: CMTime, to url: URL) async throws -> CMTime
    func cancel() async
}

actor FrameSource: FrameProviding {
    let input: FrameAsset
    private var generator: AVAssetImageGenerator?
    init(input: FrameAsset) { self.input = input }

    func catalogue() async throws -> [CMTime] {
        guard !input.disallowed, input.asset is AVURLAsset else { throw FrameExportError.unsupported }
        let tracks = try await input.asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else { throw FrameExportError.unsupported }
        let hdr = try await input.asset.loadTracks(withMediaCharacteristic: .containsHDRVideo)
        let rate = try await track.load(.nominalFrameRate)
        let formats = try await track.load(.formatDescriptions)
        guard hdr.isEmpty, !formats.isEmpty, (9.99...60.01).contains(rate),
              formats.allSatisfy({ [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC].contains(CMFormatDescriptionGetMediaSubType($0)) })
        else { throw FrameExportError.unsupported }
        // Reject HDR transfer tags too, even if a media characteristic is absent.
        for format in formats {
            let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
            if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String ||
                transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
                throw FrameExportError.unsupported
            }
        }
        let duration = try await input.asset.load(.duration)
        let entry = min(max(input.entry.seconds, 0), duration.seconds)
        guard entry.isFinite, duration.seconds > 0 else { throw FrameExportError.noFrames }
        // Compressed samples preserve PTS, including inter-frame dependencies.
        // Request a bounded window, never decode the movie from its beginning.
        let lower = max(0, entry - 0.25)
        let upper = min(duration.seconds, entry + 3.25)
        let reader = try AVAssetReader(asset: input.asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: lower, preferredTimescale: 60_000),
                                     end: CMTime(seconds: upper, preferredTimescale: 60_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FrameExportError.unsupported }
        reader.add(output)
        guard reader.startReading() else { throw FrameExportError.noFrames }
        defer { reader.cancelReading() }
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            // A compressed buffer can contain several samples or a zero-sample
            // marker. Query each sample's PTS; do not treat a buffer as a frame.
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
            for index in 0..<CMSampleBufferGetNumSamples(sample) {
                try Task.checkCancellation()
                if let attachments, index < attachments.count,
                   attachments[index][kCMSampleAttachmentKey_DoNotDisplay] as? Bool == true { continue }
                var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
                guard CMSampleBufferGetSampleTimingInfo(sample, at: index, timingInfoOut: &timing) == noErr else {
                    throw FrameExportError.unsupported
                }
                let time = timing.presentationTimeStamp
                if time.isNumeric, time.seconds >= lower, CMTimeCompare(time, duration) < 0, time.seconds <= upper {
                    times.append(time)
                }
            }
        }
        guard reader.status == .completed else { throw FrameExportError.noFrames }
        times.sort { CMTimeCompare($0, $1) < 0 }
        guard !times.isEmpty, times.count < 400 else { throw FrameExportError.noFrames }
        // Uniform measured intervals, including 1001/30000, not an assumed 1/30.
        if times.count > 1 {
            let delta = CMTimeSubtract(times[1], times[0]).seconds
            guard delta > 0, abs(delta - 1 / Double(rate)) <= 0.0001 else { throw FrameExportError.unsupported }
            for index in 1..<times.count {
                guard abs(CMTimeSubtract(times[index], times[index - 1]).seconds - delta) <= 0.00002 else {
                    throw FrameExportError.unsupported
                }
            }
        }
        let first = times.lastIndex { $0.seconds <= entry + 0.000001 } ?? 0
        let start = times[first]
        let end = CMTimeAdd(start, CMTime(value: 3, timescale: 1))
        let window = times[first...].filter { CMTimeCompare($0, end) <= 0 }
        guard !window.isEmpty else { throw FrameExportError.noFrames }
        return Array(window)
    }

    func image(at time: CMTime, fullSize: Bool = false) async throws -> FrameImage {
        try Task.checkCancellation()
        let current = AVAssetImageGenerator(asset: input.asset)
        current.appliesPreferredTrackTransform = true
        current.requestedTimeToleranceBefore = .zero
        current.requestedTimeToleranceAfter = .zero
        current.maximumSize = fullSize ? .zero : CGSize(width: 1280, height: 1280)
        generator = current
        defer { if generator === current { generator = nil } }
        let result = try await current.image(at: time)
        try Task.checkCancellation()
        guard CMTimeCompare(result.actualTime, time) == 0 else { throw FrameExportError.mismatch }
        return FrameImage(image: result.image, time: result.actualTime)
    }

    func cancel() { generator?.cancelAllCGImageGeneration() }

    func writeJPEG(at time: CMTime, to url: URL) async throws -> CMTime {
        let result = try await image(at: time, fullSize: true)
        try Task.checkCancellation()
        // Explicit 8-bit sRGB output. HDR is rejected before generating images.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: result.image.width, height: result.image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw FrameExportError.storage }
        context.draw(result.image, in: CGRect(x: 0, y: 0, width: result.image.width, height: result.image.height))
        guard let converted = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw FrameExportError.storage }
        CGImageDestinationAddImage(destination, converted, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FrameExportError.storage }
        return result.time
    }
}
