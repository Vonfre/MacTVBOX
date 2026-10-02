// Opt-in live verification: production TVClient + AVFoundation decoded frames.
// No account/library modification; no media download or signed-URL logging.
import Foundation
import AVFoundation
import CoreVideo

@main struct NativeExpansionPlaybackProbe {
    @MainActor static func decode(_ media: ResolvedMedia) async throws -> String {
        let asset = AVURLAsset(url: media.url, options: ["AVURLAssetHTTPHeaderFieldsKey": media.headers])
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true; player.play()
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        var frames = 0, dimensions = ""
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 250_000_000)
            if item.status == .failed { throw TVError.message("AVPlayer item failed (code \((item.error as NSError?)?.code ?? 0))") }
            let time = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                frames += 1; dimensions = "\(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))"
            }
            if frames >= 8 && time.seconds > 2 { return "decoded \(frames) frames, \(dimensions)" }
        }
        throw TVError.message("30s decode timeout; frames=\(frames), status=\(item.status.rawValue)")
    }
    @MainActor static func main() async {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_SPIDER"] == "1" else {
            print("Set MACTVBOX_LIVE_SPIDER=1 to enable public-network requests and short muted playback."); exit(2)
        }
        setbuf(stdout, nil)
        var failures = 0
        let filter = ProcessInfo.processInfo.environment["MACTVBOX_SOURCE_FILTER"] ?? ""
        var sources = ["csp_FirstAid", "csp_YGP", "native_TuXiaoBei", "csp_Kugou", "csp_Kanqiu"].map { Source(key: $0, name: $0, type: 3, api: $0) }
        if let path = ProcessInfo.processInfo.environment["MACTVBOX_NATIVE_CONFIG"] {
            do {
                let config = try JSONDecoder().decode(TVConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                sources += config.sources.filter { ["csp_Jpys", "csp_AppRJ", "csp_AppQi"].contains($0.api) }
            } catch { print("FAIL: could not read the explicitly supplied native configuration"); exit(2) }
        }
        let selectedSources = sources.filter { filter.isEmpty || $0.api == filter }
        guard !selectedSources.isEmpty else {
            print("FAIL: no sources matched; supply the required configuration or correct the source filter"); exit(2)
        }
        for source in selectedSources {
            let api = source.api
            do {
                let client = TVClient()
                let home = try await client.browse(source: source)
                print("HOME \(api): \(home.videos.count)")
                if let cat = home.categories.first {
                    let result = try await client.browse(source: source, category: cat.id)
                    print("CATEGORY \(api): \(result.videos.count)")
                }
                var candidates = home.videos
                if ["csp_Jpys", "csp_AppRJ", "csp_AppQi"].contains(api) {
                    do {
                        let results = try await client.browse(source: source, query: "西游记")
                        print("SEARCH \(api): \(results.videos.count)")
                        candidates = results.videos
                    } catch { print("SEARCH \(api) failed: \(sanitized(error))") }
                    if candidates.isEmpty, let cat = home.categories.first {
                        candidates = try await client.browse(source: source, category: cat.id).videos
                    }
                }
                var passed = false
                // Sample a bounded number of published items/lines. Never invent a fallback source.
                for selected in candidates.prefix(api == "csp_Kanqiu" ? 3 : 2) {
                    do {
                        let video = try await client.detail(source: source, id: selected.id)
                        print("DETAIL \(api): \(video.lines.count) lines")
                        let lines = api == "csp_Kugou" ? video.lines.filter { $0.name == "MV" } : video.lines
                        for (index, episode) in lines.compactMap({ $0.episodes.first }).prefix(3).enumerated() {
                            do {
                                let result = try await decode(client.resolve(source: source, episode: episode))
                                print("PASS \(api): \(result)"); passed = true; break
                            } catch { print("ATTEMPT \(api) line \(index + 1) failed: \(sanitized(error))") }
                        }
                        if passed { break }
                    } catch { print("DETAIL \(api) failed: \(sanitized(error))") }
                }
                if !passed { throw TVError.message("No decoded frames from sampled public lines") }
            } catch { failures += 1; print("FAIL \(api): \(sanitized(error))") }
        }
        exit(failures == 0 ? 0 : 1)
    }
    static func sanitized(_ error: Error) -> String {
        // NSError descriptions can embed signed URLs; only our local messages are safe to print.
        if let error = error as? TVError, case .message(let message) = error, !message.contains("://") { return message }
        return "\(type(of: error)) (code \((error as NSError).code))"
    }
}
