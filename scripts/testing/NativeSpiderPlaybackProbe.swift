// Opt-in real network smoke test: resolve through production adapters, then decode frames.
// No URL/token logging; no media file is saved. Existing user library is not loaded.
import Foundation
import AVFoundation
import CoreVideo

@main struct NativeSpiderPlaybackProbe {
    @MainActor static func main() async {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_SPIDER"] == "1" else {
            print("Set MACTVBOX_LIVE_SPIDER=1 to enable real network and short muted playback."); exit(2)
        }
        var failures = 0
        for (api, id) in [("csp_Bili", "BV1xx411c7mD"), ("csp_Dm84", "28")] {
            do {
                let source = Source(key: api, name: api, type: 3, api: api)
                let client = TVClient()
                let video = try await client.detail(source: source, id: id)
                guard let episode = video.lines.first?.episodes.first else { throw TVError.message("No episode") }
                let media = try await client.resolve(source: source, episode: episode)
                let asset = AVURLAsset(url: media.url, options: ["AVURLAssetHTTPHeaderFieldsKey": media.headers])
                let item = AVPlayerItem(asset: asset)
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                item.add(output)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true; player.play()
                defer { player.pause(); player.replaceCurrentItem(with: nil) }
                var frames = 0, dimensions = "", passed = false
                for _ in 0..<180 {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    if item.status == .failed { throw TVError.message(item.error?.localizedDescription ?? "AVPlayer failed") }
                    let time = player.currentTime()
                    if output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                        frames += 1; dimensions = "\(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))"
                    }
                    if frames >= 8 && time.seconds > 2 { passed = true; break }
                }
                guard passed else { throw TVError.message("45s decode timeout; frames=\(frames), status=\(item.status.rawValue)") }
                print("PASS \(api): decoded \(frames) frames, \(dimensions), time=\(player.currentTime().seconds)")
            } catch { failures += 1; print("FAIL \(api): \(error.localizedDescription)") }
        }
        exit(failures == 0 ? 0 : 1)
    }
}
