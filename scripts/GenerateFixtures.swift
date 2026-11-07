// CI-only synthetic media. No user assets or network inputs.
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let output = directory.appendingPathComponent("synthetic-video.mov")
let width = 320, height = 180, fps: Int32 = 10, sampleRate = 48_000
let samplesPerFrame = sampleRate / Int(fps)
let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000
])
writer.add(video)
writer.add(audio)
guard writer.startWriting() else { fatalError("Cannot start fixture writer") }
writer.startSession(atSourceTime: .zero)

var description = AudioStreamBasicDescription(
    mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
    mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
)
var format: CMAudioFormatDescription?
precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
    layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
    extensions: nil, formatDescriptionOut: &format) == noErr)

func waitForInput(_ input: AVAssetWriterInput) {
    let deadline = Date().addingTimeInterval(60)
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed || Date() > deadline { fatalError("Fixture encoder stalled") }
        Thread.sleep(forTimeInterval: 0.005)
    }
}

for frame in 0..<Int(fps) * 30 {
    waitForInput(video)
    var pixelBuffer: CVPixelBuffer?
    precondition(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pixelBuffer) == kCVReturnSuccess)
    let buffer = pixelBuffer!
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    let phase = CGFloat(frame % Int(fps)) / CGFloat(fps)
    context.setFillColor(CGColor(red: 0.08, green: 0.2 + 0.5 * phase, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width) * CGFloat(frame) / 300, height: 30))
    if frame == 0 {
        let png = CGImageDestinationCreateWithURL(directory.appendingPathComponent("synthetic-still.png") as CFURL,
                                                UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(png))
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    precondition(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)))

    waitForInput(audio)
    let start = frame * samplesPerFrame
    let samples: [Int16] = (0..<samplesPerFrame).map { sample in
        Int16(sin(2 * Double.pi * 440 * Double(start + sample) / Double(sampleRate)) * 5000)
    }
    var block: CMBlockBuffer?
    let byteCount = samples.count * 2
    precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
        blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
        offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block) == noErr)
    samples.withUnsafeBytes { bytes in
        precondition(CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: byteCount) == noErr)
    }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
        presentationTimeStamp: CMTime(value: Int64(start), timescale: Int32(sampleRate)), decodeTimeStamp: .invalid)
    var sampleSize = 2
    var sampleBuffer: CMSampleBuffer?
    precondition(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
        formatDescription: format, sampleCount: samples.count, sampleTimingEntryCount: 1,
        sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
        sampleBufferOut: &sampleBuffer) == noErr)
    precondition(audio.append(sampleBuffer!))
}
video.markAsFinished()
audio.markAsFinished()
let completed = DispatchSemaphore(value: 0)
writer.finishWriting { completed.signal() }
guard completed.wait(timeout: .now() + 60) == .success, writer.status == .completed else {
    fatalError("Fixture writing failed")
}
print("Created 30-second H.264/AAC synthetic video and one still image.")
