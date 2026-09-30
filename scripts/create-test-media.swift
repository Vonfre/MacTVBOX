// Creates a silent synthetic media fixture, never fetched from a third party.
import Foundation
import AVFoundation
import CoreVideo

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/fixtures/media.mp4")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let width = 640, height = 360, fps: Int32 = 24
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)
for frame in 0..<Int(fps) * 12 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var buffer: CVPixelBuffer?
    guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { fatalError("Cannot allocate video frame") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * stride + x * 4
            bytes[offset] = 255
            bytes[offset + 1] = UInt8(20 + x * 50 / width)
            bytes[offset + 2] = UInt8(65 + y * 80 / height)
            bytes[offset + 3] = 90
            if abs(x - (frame * 4) % width) < 7 { bytes[offset + 1] = 150; bytes[offset + 2] = 235; bytes[offset + 3] = 190 }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else { fatalError(writer.error!.localizedDescription) }
}
input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
guard writer.status == .completed else { fatalError(writer.error?.localizedDescription ?? "Video generation failed") }
print("Created 12-second synthetic H.264 fixture: \(output.path)")
