import Foundation
import AVFoundation
import CoreVideo

// Isolated in-memory store. Compiles with the production PlayerController below;
// never reads/writes the user's library.json. Live source access requires explicit opt-in.
@MainActor final class AppStore {
    var recorded: [String: Double] = [:]
    var writes = 0
    var explicitStarts = 0
    func beginPlayback(video: Video, source: Source) { explicitStarts += 1 }
    func resumePosition(video: Video, source: Source, episode: Episode) -> Double { recorded[episode.id] ?? 0 }
    func record(_ video: Video, source: Source, episode: Episode, position: Double) { recorded[episode.id] = position; writes += 1 }
    func friendlyError(_ error: Error) -> String { error.localizedDescription }
    func showDetail(_ video: Video, source: Source) { }
}

@main struct NativePlaybackProbe {
    @MainActor static func wait(_ label: String, timeout: Double = 50, _ condition: () -> Bool, playback: PlayerController) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let error = playback.error { throw TVError.message(error) }
            if condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw TVError.message("Timed out: " + label)
    }
    @MainActor static func frames(_ playback: PlayerController, after seconds: Double) async throws {
        try await wait("prepare item", { playback.player.currentItem != nil && playback.isReady }, playback: playback)
        guard let item = playback.player.currentItem else { throw TVError.message("No current item") }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]); item.add(output)
        defer { item.remove(output) }
        var count = 0
        try await wait("decode frames", {
            let time = playback.player.currentTime()
            if time.seconds >= seconds, output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil), CVPixelBufferGetWidth(buffer) > 0 { count += 1 }
            return count >= 8
        }, playback: playback)
        print("PASS decoded \(count) frames at \(Int(playback.position))s, \(playback.actualResolution)")
    }
    @MainActor static func main() async {
        setbuf(stdout, nil)
        do { try await run() } catch { print("FAIL " + error.localizedDescription); exit(1) }
    }
    @MainActor static func run() async throws {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_NATIVE"] == "1", CommandLine.arguments.count >= 2 else { throw TVError.message("Opt in with MACTVBOX_LIVE_NATIVE=1 and select jianpian / guazi / jpys") }
        let key = CommandLine.arguments[1]
        guard ["jianpian", "guazi", "jpys"].contains(key) else { throw TVError.message("Unknown native adapter") }
        let source: Source
        if key == "jpys" {
            guard let path = ProcessInfo.processInfo.environment["MACTVBOX_NATIVE_CONFIG"],
                  let configured = try JSONDecoder().decode(TVConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path))).sources.first(where: { $0.api == "csp_Jpys" }) else { throw TVError.message("Supply MACTVBOX_NATIVE_CONFIG with the native TVConfiguration JSON") }
            source = configured
        } else {
            source = Source(key: key, name: key, type: 3, api: key == "jianpian" ? "csp_Jianpian" : "csp_Gz360", ext: key == "jianpian" ? .string("https://api.ztcgi.com") : nil)
        }
        guard source.nativeSpider != nil, !source.usesHTTPSpider else { throw TVError.message("Expected a native-only source") }
        let client = TVClient(), store = AppStore(), playback = PlayerController()
        playback.changeVolume(0); playback.isMuted = true; playback.player.isMuted = true
        defer { playback.pause(); playback.player.replaceCurrentItem(with: nil) }
        let home = try await client.browse(source: source)
        guard !home.videos.isEmpty, let category = home.categories.first else { throw TVError.message("Empty native home/categories") }
        let categoryPage = try await client.browse(source: source, category: category.id)
        guard !categoryPage.videos.isEmpty else { throw TVError.message("Empty native category") }
        print("PASS native home / category: \(home.videos.count) / \(categoryPage.videos.count) items")
        let page = try await client.browse(source: source, query: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "西游记")
        print("PASS native search: \(page.videos.count) results")
        guard let match = page.videos.first else { throw TVError.message("Search returned no videos") }
        print("Testing first search match: \(match.title), id \(match.id)")
        let video = try await client.detail(source: source, id: match.id)
        guard video.lines.indices.contains(video.preferredLineIndex) else { throw TVError.message("No playable lines") }
        let line = video.lines[video.preferredLineIndex]
        guard let episode = line.episodes.first, line.episodes.count > 1 else { throw TVError.message("Expected multiple episodes") }
        print("PASS live search / detail: \(video.title), \(line.episodes.count) episodes")
        playback.play(video: video, source: source, episode: episode, line: line, store: store)
        try await frames(playback, after: 2)
        playback.seek(to: 90)
        try await frames(playback, after: 90)
        playback.pause()
        let paused = playback.player.currentTime().seconds
        try await Task.sleep(nanoseconds: 800_000_000)
        guard !playback.wantsPlayback, playback.player.rate == 0, abs(playback.player.currentTime().seconds - paused) < 0.3 else { throw TVError.message("Pause did not hold") }
        print("PASS pause after seek")
        playback.nextEpisode()
        guard playback.currentIndex == 1 else { throw TVError.message("Next episode not selected") }
        try await frames(playback, after: 2)
        playback.previousEpisode()
        try await frames(playback, after: 2)
        print("PASS previous episode")
        print("PASS actual native PlayerController: search → detail → decode → seek → pause → next episode → decode")
    }
}
