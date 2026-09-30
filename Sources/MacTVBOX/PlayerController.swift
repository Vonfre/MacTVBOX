import SwiftUI
import AVKit
import MacTVBOXCore

@MainActor final class PlayerController: NSObject, ObservableObject {
    let player = AVPlayer()
    @Published var isPresented = false
    @Published var theaterMode = false
    @Published var isFullScreen = false
    @Published var title = "播放器"
    @Published var subtitle = ""
    @Published var error: String?
    @Published var isBuffering = false
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var hasEnded = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var buffered: Double = 0
    @Published var currentURL: URL?
    @Published var currentEpisode: Episode?
    @Published var currentLine: PlayLine?
    @Published var rate: Float = 1
    @Published var volume: Double = 1
    @Published var isMuted = false
    @Published var autoNext = true
    @Published var fillVideo = false
    @Published var skips = PlaybackSkipSettings()
    @Published var qualities: [VideoQuality] = []
    @Published var selectedQuality = "auto"
    @Published var actualResolution = ""
    @Published var externalPlayerMessage: String?
    private var currentVideo: Video?
    private var currentSource: Source?
    private weak var store: AppStore?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var periodicObserver: Any?
    private var pendingResume: Double = 0
    private var resolveTask: Task<Void, Never>?
    private var qualityTask: Task<Void, Never>?
    private var playbackRevision = UUID()
    @Published private(set) var wantsPlayback = false
    private var seeking = false
    private var finishing = false
    private var lastSaved = Date.distantPast
    private let client = TVClient()
    private var skipLibrary: [String: PlaybackSkipSettings] = [:]
    private var skipKey: String { (currentSource?.id ?? "") + "|" + (currentVideo?.id ?? "") }

    struct VideoQuality: Identifiable {
        let width: Double
        let height: Double
        var id: String { "\(Int(width))x\(Int(height))" }
        var label: String { "\(Int(height))p" }
    }
    override init() {
        super.init()
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "player.volume") != nil { volume = min(1, max(0, defaults.double(forKey: "player.volume"))) }
        if defaults.object(forKey: "player.autoNext") != nil { autoNext = defaults.bool(forKey: "player.autoNext") }
        if let data = defaults.data(forKey: "player.titleSkips"), let saved = try? JSONDecoder().decode([String: PlaybackSkipSettings].self, from: data) { skipLibrary = saved }
        player.volume = Float(volume)
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    var canShowDetails: Bool { currentSource?.key != "direct" && currentVideo != nil }
    var hasMedia: Bool { currentEpisode != nil }
    var canSeek: Bool { isReady && duration.isFinite && duration > 0 }
    var availableLines: [PlayLine] { currentVideo?.lines ?? [] }
    var episodes: [Episode] { currentLine?.episodes ?? currentEpisode.map { [$0] } ?? [] }
    var currentIndex: Int? { episodes.firstIndex { $0.id == currentEpisode?.id } }
    var hasNext: Bool { currentIndex.map { $0 + 1 < episodes.count } ?? false }
    var hasPrevious: Bool { currentIndex.map { $0 > 0 } ?? false }
    var statusText: String {
        if error != nil { return "播放遇到问题" }
        if hasEnded { return "本集已结束" }
        if isBuffering { return currentURL == nil ? "正在解析" : "正在缓冲" }
        return isPlaying ? "正在播放" : "已暂停"
    }
    func present() { isPresented = true }
    func leavePlayer() { pause(); isPresented = false; theaterMode = false }

    func play(video: Video, source: Source, episode: Episode, line: PlayLine?, store: AppStore, userInitiated: Bool = true) {
        saveProgress()
        resolveTask?.cancel(); qualityTask?.cancel(); statusObservation = nil
        removeItemObservers()
        let revision = UUID(); playbackRevision = revision
        player.pause(); player.replaceCurrentItem(with: nil)
        self.store = store; currentVideo = video; currentSource = source
        currentEpisode = episode; currentLine = line; currentURL = nil
        title = video.title; subtitle = episode.name + " · " + source.name
        error = nil; externalPlayerMessage = nil
        isReady = false; isPlaying = false; isBuffering = true; hasEnded = false
        position = 0; duration = 0; buffered = 0; finishing = false; seeking = false
        qualities = []; selectedQuality = "auto"; actualResolution = ""
        wantsPlayback = true; isPresented = true
        skips = (skipLibrary[skipKey] ?? PlaybackSkipSettings()).normalized
        if userInitiated { store.beginPlayback(video: video, source: source) }
        pendingResume = store.resumePosition(video: video, source: source, episode: episode)
        resolveTask = Task {
            do {
                let media: ResolvedMedia
                if source.key == "direct", source.type == -2, let url = URL(string: episode.address), url.isFileURL {
                    media = ResolvedMedia(url: url, headers: [:])
                } else { media = try await client.resolve(source: source, episode: episode) }
                guard !Task.isCancelled, playbackRevision == revision else { return }
                currentURL = media.url
                replaceItem(url: media.url, headers: media.headers)
            } catch {
                guard !Task.isCancelled, playbackRevision == revision else { return }
                self.error = "播放解析失败：\(store.friendlyError(error))\n可重试或在右侧切换线路，也可返回详情选择其他来源。"
                isBuffering = false; wantsPlayback = false
            }
        }
    }
    func playDirect(_ url: URL, store: AppStore) {
        let title = url.deletingPathExtension().lastPathComponent.isEmpty ? "网络视频" : url.deletingPathExtension().lastPathComponent
        let video = Video(id: url.absoluteString, title: title)
        let source = Source(key: "direct", name: url.isFileURL ? "本地文件" : "直链播放", type: -2, api: "")
        play(video: video, source: source, episode: Episode(name: "直接播放", address: url.absoluteString), line: nil, store: store)
    }
    private func removeItemObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil; failureObserver = nil
    }
    private func replaceItem(url: URL, headers: [String: String]) {
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.error = "无法播放：\(item.error?.localizedDescription ?? "不支持的媒体格式")\n请重试或选择其他线路。"
                    self.isBuffering = false; self.wantsPlayback = false; self.isReady = false
                } else if item.status == .readyToPlay {
                    self.isReady = true
                    self.duration = item.duration.seconds.isFinite ? max(0, item.duration.seconds) : 0
                    let start = PlaybackPolicy.startPosition(resume: self.pendingResume, duration: self.duration, skips: self.skips)
                    self.pendingResume = 0
                    if start > 0, self.canSeek { self.seek(to: start) }
                    else if self.wantsPlayback { self.player.playImmediately(atRate: self.rate) }
                    self.loadQualities(asset, item: item)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.finishEpisode()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "媒体连接已中断。"
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.error = message; self.pause(); self.isBuffering = false
            }
        }
        player.replaceCurrentItem(with: item)
    }
    private func tick() {
        guard let item = player.currentItem else { return }
        let seconds = player.currentTime().seconds
        if !seeking, seconds.isFinite { position = max(0, seconds) }
        let length = item.duration.seconds
        duration = length.isFinite ? max(0, length) : 0
        buffered = item.loadedTimeRanges.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds }.filter { $0.isFinite }.max() ?? 0
        isPlaying = player.timeControlStatus == .playing
        isBuffering = error == nil && wantsPlayback && (!isReady || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        let size = item.presentationSize
        actualResolution = size.height > 0 ? "\(Int(size.width)) × \(Int(size.height))" : ""
        if Date().timeIntervalSince(lastSaved) > 5 { saveProgress(); lastSaved = Date() }
        if wantsPlayback, isPlaying, !seeking, PlaybackPolicy.shouldFinish(position: position, duration: duration, skips: skips) { finishEpisode() }
    }
    func togglePlayback() {
        guard error == nil, hasMedia else { return }
        if wantsPlayback { pause() }
        else {
            wantsPlayback = true
            if hasEnded { hasEnded = false; finishing = false; seek(to: PlaybackPolicy.startPosition(resume: 0, duration: duration, skips: skips)) }
            else if isReady { player.playImmediately(atRate: rate) }
        }
    }
    func pause() { wantsPlayback = false; player.pause(); isPlaying = false; isBuffering = false; saveProgress() }
    func seek(to target: Double) {
        guard let value = PlaybackPolicy.seekPosition(target, duration: duration), let item = player.currentItem, isReady else { return }
        item.cancelPendingSeeks()
        seeking = true; position = value; hasEnded = false; finishing = false
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.player.currentItem === item, finished else { return }
                self.seeking = false
                if self.wantsPlayback { self.player.playImmediately(atRate: self.rate) }
                self.saveProgress()
            }
        }
    }
    func skip(by seconds: Double) { seek(to: position + seconds) }
    private func finishEpisode() {
        guard !finishing else { return }
        finishing = true; saveProgress()
        if autoNext && hasNext && wantsPlayback, let index = currentIndex { selectEpisode(episodes[index + 1], userInitiated: false) }
        else { pause(); hasEnded = true }
    }
    func selectEpisode(_ episode: Episode, userInitiated: Bool = true) {
        guard let currentVideo, let currentSource, let store else { return }
        play(video: currentVideo, source: currentSource, episode: episode, line: currentLine, store: store, userInitiated: userInitiated)
    }
    func nextEpisode() { if let index = currentIndex, hasNext { selectEpisode(episodes[index + 1]) } }
    func previousEpisode() { if let index = currentIndex, hasPrevious { selectEpisode(episodes[index - 1]) } }
    func retryPlayback() { if let currentEpisode { selectEpisode(currentEpisode) } }
    func switchLine(_ line: PlayLine) {
        guard let currentVideo, let currentSource, let store,
              let episode = line.episodes.first(where: { $0.name == currentEpisode?.name }) ?? line.episodes.first else { return }
        play(video: currentVideo, source: currentSource, episode: episode, line: line, store: store)
    }
    func showDetails() {
        guard canShowDetails, let currentVideo, let currentSource, let store else { return }
        leavePlayer(); store.showDetail(currentVideo, source: currentSource)
    }
    func saveProgress() {
        guard let currentVideo, let currentSource, let currentEpisode, player.currentItem?.status == .readyToPlay, !seeking else { return }
        store?.record(currentVideo, source: currentSource, episode: currentEpisode, position: player.currentTime().seconds)
    }
    func changeRate(_ value: Float) { rate = value; if wantsPlayback && isReady { player.rate = value } }
    func changeVolume(_ value: Double) {
        volume = min(1, max(0, value)); player.volume = Float(volume)
        if volume > 0 { isMuted = false; player.isMuted = false }
        UserDefaults.standard.set(volume, forKey: "player.volume")
    }
    func toggleMute() { isMuted.toggle(); player.isMuted = isMuted }
    func setAutoNext(_ value: Bool) { autoNext = value; UserDefaults.standard.set(value, forKey: "player.autoNext") }
    func setSkips(opening: Double? = nil, ending: Double? = nil) {
        skips = PlaybackSkipSettings(opening: opening ?? skips.opening, ending: ending ?? skips.ending)
        skipLibrary[skipKey] = skips
        if let data = try? JSONEncoder().encode(skipLibrary) { UserDefaults.standard.set(data, forKey: "player.titleSkips") }
    }
    private func loadQualities(_ asset: AVURLAsset, item: AVPlayerItem) {
        qualityTask?.cancel()
        qualityTask = Task {
            guard let variants = try? await asset.load(.variants), !Task.isCancelled, player.currentItem === item else { return }
            var unique: [String: VideoQuality] = [:]
            for variant in variants {
                guard let size = variant.videoAttributes?.presentationSize, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { continue }
                let quality = VideoQuality(width: size.width, height: size.height)
                unique[quality.id] = quality
            }
            qualities = unique.values.sorted { $0.height < $1.height }
        }
    }
    func selectQuality(_ id: String) {
        selectedQuality = id
        let quality = qualities.first { $0.id == id }
        // AVPlayer's ABR remains active. This is an upper bound, not a forced rendition.
        player.currentItem?.preferredMaximumResolution = quality.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }
    var vlcApplication: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") }
    func openVLC() {
        guard let url = currentURL, let app = vlcApplication else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error { self.externalPlayerMessage = error.localizedDescription }
                else if self.currentURL == url { self.pause() }
            }
        }
    }
}
