@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct FrameInputFlags: Sendable {
    var adjustmentData = false
    var adjustmentBaseVideo = false
    var highFrameRate = false
    var timelapse = false
    var videoComposition = false
    var rejection: FrameExportError? {
        if adjustmentData || adjustmentBaseVideo { return .adjusted }
        if highFrameRate { return .highFrameRateCapture }
        if timelapse { return .timelapse }
        if videoComposition { return .videoComposition }
        return nil
    }
    var report: String {
        "adjustmentData=\(adjustmentData) adjustmentBaseVideo=\(adjustmentBaseVideo) highFrameRate=\(highFrameRate) timelapse=\(timelapse) videoComposition=\(videoComposition)"
    }
}

/// AVAsset is read-only; the actor owns its readers/generators, never an AVPlayer.
struct FrameAsset: @unchecked Sendable {
    let asset: AVAsset
    let entry: CMTime
    var flags = FrameInputFlags()
    let fileStem: String
}
struct FrameImage: @unchecked Sendable {
    let image: CGImage
    /// Canonical measured presentation time, after checking generator actualTime.
    let time: CMTime
}
protocol FrameProviding: Sendable {
    func catalogue() async throws -> [CMTime]
    func image(at time: CMTime, fullSize: Bool) async throws -> FrameImage
    func writeJPEG(at time: CMTime, to url: URL) async throws -> CMTime
    func cancel() async
    func diagnosticReport() async -> String
}
extension FrameProviding {
    func diagnosticReport() async -> String { "source=unavailable" }
}

enum FrameColor {
    static func sRGB(_ image: CGImage) throws -> CGImage {
        guard let input = image.colorSpace, input.model == .rgb else { throw FrameExportError.colorProfile }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw FrameExportError.colorConversion }
        // Drawing converts tagged source primaries/transfer into sRGB AFTER
        // AVFoundation tone mapping. Relabeling a profile is not conversion.
        context.setRenderingIntent(.perceptual)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage() else { throw FrameExportError.colorConversion }
        return converted
    }
}

actor FrameSource: FrameProviding {
    let input: FrameAsset
    private var generator: AVAssetImageGenerator?
    private var frameTimes: [CMTime] = []
    private var notes: [String] = []
    private var lastResult = "not-started"
    private var imageResult = "not-generated"
    private var isHDR = false
    init(input: FrameAsset) { self.input = input }

    func diagnosticReport() async -> String {
        ([input.flags.report] + notes + [lastResult, imageResult]).joined(separator: "\n")
    }
    private func failure(_ error: Error, fallback: FrameExportError, stage: String) -> Error {
        let ns = error as NSError
        let domain = [AVFoundationErrorDomain, NSOSStatusErrorDomain, NSCocoaErrorDomain, NSURLErrorDomain].contains(ns.domain) ? ns.domain : "other"
        let reason = (error as? FrameExportError) ?? fallback
        lastResult = "stage=\(stage) reason=\(reason.rawValue) system=\(domain):\(ns.code)"
        return error is CancellationError ? error : reason
    }
    private func colorTag(_ value: CFPropertyList?) -> String {
        guard let string = value as? String else { return "unspecified" }
        // Never copy arbitrary profile names/metadata from a user's file.
        if string == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String { return "PQ" }
        if string == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String { return "HLG" }
        if string == "ITU_R_709_2" { return "709" }
        if string == "ITU_R_2020" { return "2020" }
        if string == "P3_D65" { return "P3-D65" }
        if string == "sRGB" { return "sRGB" }
        return "other"
    }

    func catalogue() async throws -> [CMTime] {
        notes = []; frameTimes = []; imageResult = "not-generated"
        do { return try await readCatalogue() }
        catch { throw failure(error, fallback: .readFailed, stage: "catalogue") }
    }
    private func readCatalogue() async throws -> [CMTime] {
        let tracks = try await input.asset.loadTracks(withMediaType: .video)
        notes.append("asset=\(input.asset is AVURLAsset ? "url" : "composition") tracks=\(tracks.count)")
        guard let track = tracks.first else { throw FrameExportError.multipleTracks }
        let rate = try await track.load(.nominalFrameRate)
        let formats = try await track.load(.formatDescriptions)
        let hdrTracks = try await input.asset.loadTracks(withMediaCharacteristic: .containsHDRVideo)
        isHDR = !hdrTracks.isEmpty
        notes.append(String(format: "nominalFPS=%.6f hdrCharacteristic=%@", rate.isFinite ? rate : 0, isHDR ? "true" : "false"))
        for format in formats {
            let transfer = colorTag(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction))
            let primaries = colorTag(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries))
            let matrix = colorTag(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix))
            if transfer == "HLG" || transfer == "PQ" { isHDR = true }
            notes.append(String(format: "codec=0x%08x transfer=%@ primaries=%@ matrix=%@", CMFormatDescriptionGetMediaSubType(format), transfer, primaries, matrix))
        }
        if let reason = input.flags.rejection { throw reason }
        guard input.asset is AVURLAsset else { throw FrameExportError.assetComposition }
        guard tracks.count == 1 else { throw FrameExportError.multipleTracks }
        guard !formats.isEmpty else { throw FrameExportError.missingFormat }
        guard formats.allSatisfy({ [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC].contains(CMFormatDescriptionGetMediaSubType($0)) }) else { throw FrameExportError.codec }
        if #available(iOS 18.0, *) { notes.append("toneMapping=AVAssetImageGenerator.forceSDR colorConversion=tagged-source-to-sRGB") }
        else {
            guard !isHDR else { throw FrameExportError.hdrRequiresNewerOS }
            notes.append("toneMapping=SDR-source colorConversion=tagged-source-to-sRGB")
        }
        let duration = try await input.asset.load(.duration)
        guard input.entry.isNumeric, duration.isNumeric, duration.seconds > 0 else { throw FrameExportError.invalidTiming }
        let entry = min(max(input.entry.seconds, 0), duration.seconds)
        // Bounded compressed metadata, including a preceding frame for sparse
        // VFR. This does not decode a two-hour movie from its beginning.
        let lower = max(0, entry - 3), upper = min(duration.seconds, entry + 3.25)
        notes.append(String(format: "metadataWindowSeconds=%.4f", upper - lower))
        let reader = try AVAssetReader(asset: input.asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: lower, preferredTimescale: 60_000),
                                      end: CMTime(seconds: upper, preferredTimescale: 60_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FrameExportError.readFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? FrameExportError.readFailed }
        defer { reader.cancelReading() }
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[String: Any]]
            let outputTimes = try FrameTiming.outputTimes(sample)
            for (index, time) in outputTimes.enumerated() {
                try Task.checkCancellation()
                if let attachments, index < attachments.count,
                   attachments[index][kCMSampleAttachmentKey_DoNotDisplay as String] as? Bool == true { continue }
                if time.seconds >= lower, CMTimeCompare(time, duration) < 0, time.seconds <= upper { times.append(time) }
                guard times.count <= 4096 else { throw FrameExportError.tooManyFrames }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? FrameExportError.readFailed }
        let unique = FrameTiming.uniqueSorted(times)
        notes.append("duplicatePTS=\(times.count - unique.count)")
        guard !unique.isEmpty else { throw FrameExportError.noFrames }
        notes.append(String(format: "firstPTSRelativeToEntry=%.9fs", unique[0].seconds - entry))
        frameTimes = try FrameSelection.window(unique, entry: entry)
        notes.append(FrameTiming.report(frameTimes))
        lastResult = "stage=catalogue result=ready"
        return frameTimes
    }

    func image(at time: CMTime, fullSize: Bool = false) async throws -> FrameImage {
        do {
            try Task.checkCancellation()
            guard let index = frameTimes.firstIndex(where: { CMTimeCompare($0, time) == 0 }) else { throw FrameExportError.invalidTiming }
            let current = AVAssetImageGenerator(asset: input.asset)
            current.appliesPreferredTrackTransform = true
            if #available(iOS 18.0, *) { current.dynamicRangePolicy = .forceSDR }
            else if isHDR { throw FrameExportError.hdrRequiresNewerOS }
            current.requestedTimeToleranceBefore = .zero
            current.requestedTimeToleranceAfter = .zero
            current.maximumSize = fullSize ? .zero : CGSize(width: 1280, height: 1280)
            generator = current
            defer { if generator === current { generator = nil } }
            let result = try await current.image(at: time)
            try Task.checkCancellation()
            guard FrameTiming.matches(actual: result.actualTime, index: index, times: frameTimes) else { throw FrameExportError.mismatch }
            let converted = try FrameColor.sRGB(result.image)
            imageResult = String(format: "image=SDR-sRGB8 sourceTagged=%@ actualTimeDelta=%.9fs mode=%@", result.image.colorSpace == nil ? "false" : "true", CMTimeSubtract(result.actualTime, time).seconds, fullSize ? "full" : "preview")
            lastResult = "stage=image result=ready"
            return FrameImage(image: converted, time: frameTimes[index])
        } catch { throw failure(error, fallback: .imageFailed, stage: "image") }
    }
    func cancel() { generator?.cancelAllCGImageGeneration() }

    func writeJPEG(at time: CMTime, to url: URL) async throws -> CMTime {
        let result = try await image(at: time, fullSize: true)
        try Task.checkCancellation()
        // ImageIO embeds the converted CGImage's sRGB profile; the name alone
        // would not convert or correctly tag the original wide-gamut pixels.
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw FrameExportError.storage }
        CGImageDestinationAddImage(destination, result.image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FrameExportError.storage }
        return result.time
    }
}
