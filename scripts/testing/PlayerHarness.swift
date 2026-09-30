import Foundation
import AVFoundation

// Isolated in-memory store. Compiles with the production PlayerController below;
// never reads/writes the user's library.json or requests third-party film sources.
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

@main struct PlayerHarness {
    @MainActor static func wait(_ label: String, seconds: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "Harness", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out: " + label])
    }
    @MainActor static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw NSError(domain: "Harness", code: 2, userInfo: [NSLocalizedDescriptionKey: label]) }
        print("PASS " + label)
    }
    @MainActor static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let defaults = UserDefaults.standard
        // This binary's preferences domain is not the application bundle domain.
        for key in ["player.titleSkips", "player.volume", "player.autoNext"] { defaults.removeObject(forKey: key) }
        let store = AppStore(), playback = PlayerController()
        let first = Episode(name: "第一集", address: url.absoluteString)
        let second = Episode(name: "第二集", address: url.absoluteString + "?episode=2")
        let line = PlayLine(name: "本地合成视频", episodes: [first, second])
        var video = Video(id: "isolated-test", title: "播放器集成测试"); video.lines = [line]
        let source = Source(key: "direct", name: "本地测试", type: -2, api: "")
        playback.play(video: video, source: source, episode: first, line: line, store: store)
        playback.pause()
        try await wait("ready while paused") { playback.isReady }
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(playback.player.rate == 0 && !playback.wantsPlayback, "pause during preparation remains paused")
        try check(playback.isPresented && playback.hasNext && !playback.hasPrevious, "embedded route and episode capabilities")
        playback.seek(to: 5)
        try await wait("paused seek") { abs(playback.player.currentTime().seconds - 5) < 0.15 }
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(playback.player.rate == 0, "seeking while paused does not autoplay")
        playback.seek(to: 1)
        playback.skip(by: 5); playback.skip(by: 5); playback.skip(by: -5)
        try check(abs(playback.position - 6) < 0.01, "rapid repeated seeks accumulate using the pending target")
        try await wait("repeat seek settles") { abs(playback.player.currentTime().seconds - 6) < 0.15 }
        try check(playback.player.rate == 0 && !playback.wantsPlayback, "repeated seeks preserve pause")
        playback.skip(by: -100)
        try check(playback.position == 0, "repeated backward seek clamps to start")
        playback.skip(by: 100)
        try check(playback.position <= playback.duration && playback.position > 10, "repeated forward seek clamps to duration")
        playback.seek(to: 5)
        try await wait("seek after clamping") { abs(playback.player.currentTime().seconds - 5) < 0.15 }
        playback.changeRate(1.5)
        try check(playback.player.rate == 0 && playback.rate == 1.5, "changing speed preserves pause")
        playback.changeVolume(0.35); playback.toggleMute()
        try check(playback.player.isMuted && abs(playback.player.volume - 0.35) < 0.01, "volume and mute control real AVPlayer")
        playback.changeVolume(0.5)
        try check(!playback.player.isMuted, "volume change unmutes")
        playback.changeRate(1)
        playback.setSkips(opening: 2, ending: 2)
        playback.setAutoNext(false)
        playback.nextEpisode()
        try await wait("second episode opening") { playback.currentEpisode?.id == second.id && playback.isPlaying && playback.position >= 2 }
        playback.pause()
        try check(playback.position < 4 && playback.hasPrevious && !playback.hasNext, "next episode applies per-title opening")
        playback.seek(to: 10.2); playback.togglePlayback()
        try await wait("ending pause") { playback.hasEnded }
        try check(!playback.wantsPlayback && playback.player.rate == 0, "ending skip pauses with automatic next disabled")
        playback.togglePlayback()
        try await wait("replay") { playback.isPlaying && playback.position >= 2 && playback.position < 4 }
        try check(!playback.hasEnded, "replay restarts after opening instead of remaining in credits")
        playback.setAutoNext(true)
        playback.previousEpisode()
        try await wait("first ready") { playback.currentEpisode?.id == first.id && playback.isReady }
        let startsBeforeAutomaticNext = store.explicitStarts
        playback.seek(to: 10.3)
        try await wait("automatic second") { playback.currentEpisode?.id == second.id && playback.isReady }
        try check(playback.skips == PlaybackSkipSettings(opening: 2, ending: 2), "automatic next preserves title skip settings")
        try check(store.explicitStarts == startsBeforeAutomaticNext, "automatic next does not reset deleted-history protection")
        playback.seek(to: 10.4)
        try await wait("last ends") { playback.hasEnded }
        try check(playback.currentEpisode?.id == second.id && !playback.wantsPlayback, "last episode ends without loop")
        playback.selectEpisode(first); playback.leavePlayer()
        try await wait("ready after leave") { playback.isReady }
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(!playback.isPresented && playback.player.rate == 0, "leaving during load cannot start hidden playback")
        playback.present()
        try check(playback.isPresented && playback.player.rate == 0, "returning to player preserves paused state")
        let restored = PlayerController()
        restored.play(video: video, source: source, episode: first, line: line, store: store); restored.pause()
        try check(restored.skips == playback.skips && abs(restored.volume - 0.5) < 0.01, "title skips and volume persist across controllers")
        let other = Video(id: "other-title", title: "另一部影片")
        restored.play(video: other, source: source, episode: first, line: line, store: store); restored.pause()
        try check(restored.skips == PlaybackSkipSettings(), "different titles do not inherit skip offsets")
        try check(store.writes > 0, "playback writes progress through store")
        if ProcessInfo.processInfo.environment["MACTVBOX_LIVE_HLS"] == "1" {
            let sample = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!
            restored.playDirect(sample, store: store)
            restored.pause()
            try await wait("Apple HLS variants", seconds: 45) { restored.qualities.count > 1 }
            let quality = restored.qualities.first!
            restored.selectQuality(quality.id)
            try check(restored.player.currentItem?.preferredMaximumResolution.height == CGFloat(quality.height),
                      "HLS menu sets actual AVPlayer maximum resolution")
            restored.selectQuality("auto")
            try check(restored.player.currentItem?.preferredMaximumResolution == .zero, "HLS auto clears resolution limit")
            print("LIVE HLS qualities: " + restored.qualities.map(\.label).joined(separator: ", "))
        }
        print("PLAYER INTEGRATION PASSED (production controller, local synthetic media)")
        playback.pause(); restored.pause()
    }
}
