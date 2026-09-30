// Verifies AVFoundation decoding, not merely a successful playlist HTTP response.
import Foundation
import AVFoundation
import CoreVideo

@main struct PlaybackProbe {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: probe <file-containing-media-url>") }
        let address = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let item = AVPlayerItem(url: URL(string: address)!)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        var frameCount = 0
        for _ in 0..<180 {
            try await Task.sleep(nanoseconds: 250_000_000)
            if item.status == .failed { print("FAILED: \(item.error?.localizedDescription ?? "unknown")"); exit(1) }
            let time = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                frameCount += 1
                if frameCount == 1 { print("DECODED \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))") }
            }
            if frameCount >= 8 && time.seconds > 2 {
                print("PASS actual video frames=\(frameCount), playbackTime=\(time.seconds), duration=\(item.duration.seconds)")
                player.pause(); exit(0)
            }
        }
        print("TIMEOUT status=\(item.status.rawValue), frames=\(frameCount), time=\(player.currentTime().seconds), error=\(String(describing: item.error))")
        exit(1)
    }
}
