import SwiftUI
import AVFoundation
import AppKit
import MacTVBOXCore

/// Only a video layer: no AVPlayerView, floating system transport, or pause overlay.
private final class VideoLayerView: NSView {
    let videoLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}
private struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let fill: Bool
    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView(frame: .zero); view.videoLayer.player = player; return view
    }
    func updateNSView(_ view: VideoLayerView, context: Context) {
        view.videoLayer.player = player
        view.videoLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
    static func dismantleNSView(_ view: VideoLayerView, coordinator: ()) { view.videoLayer.player = nil }
}

struct PlayerPage: View {
    @EnvironmentObject var playback: PlayerController
    @StateObject private var chrome = PlayerChromeController()
    @State private var activePanel: String?
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    private var interacting: Bool { scrubbing || activePanel != nil }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                screen
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    if let error = playback.error { errorPanel(error) }
                    if let message = playback.externalPlayerMessage {
                        Text(message).font(.caption).foregroundStyle(.orange).padding(12).background(.black.opacity(0.8))
                    }
                    transport
                }
                .opacity(chrome.visible ? 1 : 0)
                .allowsHitTesting(chrome.visible)
                .accessibilityHidden(!chrome.visible)
                .animation(.easeInOut(duration: 0.25), value: chrome.visible)
                if activePanel != nil {
                    inlinePanel(maxHeight: max(240, min(460, geometry.size.height - 210)))
                        .background(Color(white: 0.09).opacity(0.98), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
                        .padding(.trailing, 22).padding(.bottom, 112)
                }
        }
        }

        .background(.black)
        .background(PlayerWindowReader(chrome: chrome).frame(width: 0, height: 0))
        .onAppear {
            chrome.seekBy = { seconds in
                guard playback.canSeek else { return false }
                playback.skip(by: seconds)
                return true
            }
            chrome.onFullScreenChange = { playback.isFullScreen = $0 }
            chrome.dismissPanel = {
                guard activePanel != nil else { return false }
                activePanel = nil; return true
            }
            updateChrome()
        }
        .onDisappear { chrome.detach(); chrome.seekBy = nil; chrome.dismissPanel = nil; chrome.onFullScreenChange = nil }
        .onChange(of: playback.isPlaying) { _ in updateChrome() }
        .onChange(of: playback.error) { _ in updateChrome() }
        .onChange(of: activePanel) { _ in updateChrome() }
        .onChange(of: scrubbing) { _ in updateChrome() }
        .onChange(of: playback.currentEpisode?.id) { _ in scrubbing = false; chrome.activity() }
    }
    private func updateChrome() {
        chrome.update(playing: playback.isPlaying && playback.error == nil, interacting: interacting)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Button { playback.leavePlayer() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(IconButton(size: 36)).help("返回媒体库并暂停").accessibilityLabel("返回媒体库并暂停")
            VStack(alignment: .leading, spacing: 4) {
                Text(playback.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(playback.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(playback.statusText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 35)
        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
        .onHover { chrome.hoverControls($0) }
    }
    private var screen: some View {
        ZStack {
            Color.black
            VideoSurface(player: playback.player, fill: playback.fillVideo).clipped().allowsHitTesting(false)
            if playback.currentURL == nil {
                VStack(spacing: 14) {
                    if playback.error == nil { ProgressView().controlSize(.large) }
                    else { Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(Theme.muted) }
                    Text(playback.error == nil ? "正在准备影片" : "暂时无法播放").font(.headline)
                    Text(playback.error == nil ? "正在请求片源并解析媒体地址" : "请查看下方提示，或切换其他线路")
                        .font(.caption).foregroundStyle(Theme.muted)
                }.allowsHitTesting(false)
            } else if playback.isBuffering {
                ProgressView().controlSize(.large).allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if activePanel != nil { activePanel = nil } else { chrome.toggleFullScreen() } }
        .onTapGesture {
            if activePanel != nil { activePanel = nil } else { playback.togglePlayback() }
            chrome.activity()
        }
        .help("单击播放或暂停；双击全屏；← / → 快退快进 5 秒，按住连续；全屏闲置 3 秒隐藏界面")
    }
    private var transport: some View {
        VStack(spacing: 5) {
            Slider(value: Binding(get: { scrubbing ? scrubPosition : playback.position }, set: { value in
                scrubPosition = value
                // Keyboard / accessibility adjustments may not open a drag session.
                if !scrubbing { playback.seek(to: value) }
                chrome.activity()
            }), in: 0...max(playback.duration, 1), onEditingChanged: { editing in
                if editing { scrubPosition = playback.position; scrubbing = true }
                else { playback.seek(to: scrubPosition); scrubbing = false }
            })
            .disabled(!playback.canSeek).accessibilityLabel("播放进度")
            HStack(spacing: 6) {
                Button { playback.togglePlayback(); chrome.activity() } label: {
                    Image(systemName: playback.wantsPlayback ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .semibold))
                }
                .buttonStyle(IconButton(size: 38)).keyboardShortcut(.space, modifiers: [])
                .disabled(playback.error != nil).accessibilityLabel(playback.wantsPlayback ? "暂停" : playback.hasEnded ? "重新播放" : "播放")
                transportButton("上一集", icon: "backward.end.fill", disabled: !playback.hasPrevious) { playback.previousEpisode() }
                transportButton("下一集", icon: "forward.end.fill", disabled: !playback.hasNext) { playback.nextEpisode() }
                Text("\(PlaybackPolicy.timeText(scrubbing ? scrubPosition : playback.position)) / \(PlaybackPolicy.timeText(playback.duration > 0 ? playback.duration : .nan))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).fixedSize()
                    .padding(.leading, 5)
                Spacer(minLength: 4)
                panelButton("quality", label: qualityLabel, accessibility: "清晰度上限")
                panelButton("speed", label: String(format: "%.2g×", playback.rate), accessibility: "播放速度")
                panelButton("episodes", icon: "list.bullet", accessibility: "选集与线路")
                panelButton("volume", icon: playback.isMuted || playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibility: "音量与静音")
                panelButton("settings", icon: "gearshape", accessibility: "播放设置")
                transportButton(playback.theaterMode ? "退出影院模式" : "影院模式", icon: "rectangle", disabled: chrome.isFullScreen) { playback.theaterMode.toggle() }
                Button { chrome.toggleFullScreen() } label: {
                    Image(systemName: chrome.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .semibold))
                }.buttonStyle(IconButton(size: 38))
                    .help(chrome.isFullScreen ? "退出全屏（Esc）" : "全屏（也可双击画面）")
                    .accessibilityLabel(chrome.isFullScreen ? "退出全屏" : "全屏")
            }.foregroundStyle(.white)
        }
        .padding(.horizontal, 22).padding(.bottom, 16).padding(.top, 32)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom))
        .onHover { chrome.hoverControls($0) }
    }
    private func transportButton(_ label: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button { action(); chrome.activity() } label: { Image(systemName: icon) }
            .buttonStyle(IconButton(size: 34)).disabled(disabled).help(label).accessibilityLabel(label)
    }
    private func panelButton(_ id: String, label: String? = nil, icon: String? = nil, accessibility: String) -> some View {
        Button { activePanel = activePanel == id ? nil : id; chrome.activity() } label: {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 15)) }
                else { Text(label ?? accessibility).font(.system(size: 12, weight: .semibold)) }
            }.padding(.horizontal, 8).frame(minWidth: 30, minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(accessibility).accessibilityLabel(accessibility)
        .foregroundStyle(activePanel == id ? Theme.accent : .white)
    }
    @ViewBuilder private func inlinePanel(maxHeight: CGFloat) -> some View {
        switch activePanel {
        case "settings":
            VStack(alignment: .leading, spacing: 16) { panelHeading("播放设置"); settingsPanel }
                .frame(width: 300, height: maxHeight).padding(20)
        case "episodes":
            VStack(alignment: .leading, spacing: 16) { panelHeading("选集与线路"); episodePanel }
                .frame(width: 300, height: min(400, maxHeight)).padding(20)
        case "quality": qualityPanel
        case "speed": speedPanel
        case "volume": volumePanel
        default: EmptyView()
        }
    }
    private func panelHeading(_ title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button { activePanel = nil } label: { Image(systemName: "xmark") }.buttonStyle(IconButton(size: 28)).accessibilityLabel("关闭" + title)
        }
    }
    private var qualityLabel: String { playback.qualities.first { $0.id == playback.selectedQuality }?.label ?? "自动" }
    private var qualityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeading("清晰度上限")
            if playback.qualities.count > 1 {
                choiceRow("自动", selected: playback.selectedQuality == "auto") { playback.selectQuality("auto"); activePanel = nil }
                ForEach(playback.qualities) { quality in
                    choiceRow(quality.label, selected: playback.selectedQuality == quality.id) { playback.selectQuality(quality.id); activePanel = nil }
                }
                Text("限制最高分辨率，网络不佳时仍可能降低画质。").font(.caption).foregroundStyle(Theme.muted)
            } else {
                Text("原始 / 自动").font(.callout)
                Text("当前媒体没有提供多档 HLS 清晰度，不额外转码或虚构画质选项。").font(.caption).foregroundStyle(Theme.muted)
            }
            if !playback.actualResolution.isEmpty { Text("当前画面  " + playback.actualResolution).font(.caption).foregroundStyle(Theme.accent) }
        }.frame(width: 230).padding(18)
    }
    private var speedPanel: some View {
        VStack(spacing: 8) {
            panelHeading("播放速度")
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                choiceRow(String(format: "%.2g×", rate), selected: playback.rate == rate) { playback.changeRate(rate); activePanel = nil }
            }
        }.frame(width: 170).padding(18)
    }
    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) } }
                .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
        }.buttonStyle(SurfaceButton(selected: selected))
    }
    private var volumePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading("音量")
            HStack {
                Button { playback.toggleMute() } label: { Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    .buttonStyle(IconButton()).accessibilityLabel("静音 / 恢复音量")
                Slider(value: Binding(get: { playback.volume }, set: { playback.changeVolume($0) }), in: 0...1).accessibilityLabel("音量")
                Text("\(Int(playback.volume * 100))%").font(.system(size: 11, design: .monospaced)).frame(width: 35)
            }
        }.frame(width: 240).padding(18)
    }
    private var episodePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !playback.availableLines.isEmpty {
                Text("播放线路").font(.caption).foregroundStyle(Theme.muted)
                Picker("播放线路", selection: Binding(get: { playback.currentLine?.id ?? "" }, set: { id in
                    if let line = playback.availableLines.first(where: { $0.id == id }) { playback.switchLine(line) }
                })) {
                    ForEach(playback.availableLines) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            HStack {
                Text("全部剧集").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(playback.episodes.count) 集").font(.caption).foregroundStyle(Theme.muted)
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(playback.episodes) { episode in
                            Button { playback.selectEpisode(episode) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: episode.id == playback.currentEpisode?.id ? "play.fill" : "play")
                                        .font(.system(size: 10)).foregroundStyle(Theme.accent)
                                    Text(episode.name).font(.system(size: 12)).lineLimit(2)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 42).contentShape(Rectangle())
                            }.buttonStyle(SurfaceButton(selected: episode.id == playback.currentEpisode?.id)).id(episode.id)
                        }
                    }
                }
                .onAppear { scroll.scrollTo(playback.currentEpisode?.id, anchor: .center) }
                .onChange(of: playback.currentEpisode?.id) { id in scroll.scrollTo(id, anchor: .center) }
            }
            Button { playback.showDetails() } label: { Label("影片详情与其他来源", systemImage: "square.stack") }.buttonStyle(QuietButton()).disabled(!playback.canShowDetails)
            Text("切换线路不等于切换清晰度；不同线路可能有不同版本或集数。")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    settingsHeading("连续播放", icon: "play.rectangle.on.rectangle")
                    Toggle("自动播放下一集", isOn: Binding(get: { playback.autoNext }, set: { playback.setAutoNext($0) })).font(.caption)
                    Text("关闭后，在片尾跳过点或本集结束时暂停。最后一集不会循环播放。")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    settingsHeading("片头与片尾", icon: "scissors")
                    Text("仅保存到当前影片，后续剧集沿用。0 秒表示关闭。")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    skipControl("跳过片头", value: playback.skips.opening) { playback.setSkips(opening: $0) }
                    skipControl("跳过片尾", value: playback.skips.ending) { playback.setSkips(ending: $0) }
                    Button("当前位置设为片头结束") { playback.setSkips(opening: playback.position) }.buttonStyle(QuietButton()).disabled(!playback.canSeek)
                    Button("当前位置设为片尾开始") { playback.setSkips(ending: playback.duration - playback.position) }.buttonStyle(QuietButton()).disabled(!playback.canSeek)
                    Button("重置本片设置") { playback.setSkips(opening: 0, ending: 0) }.font(.caption).buttonStyle(.plain).foregroundStyle(Theme.muted)
                    Text("片头在下次开播时生效；片尾在播放到设定位置时生效。若设置超过视频长度，将忽略跳过。")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    settingsHeading("画面", icon: "rectangle.on.rectangle")
                    Picker("清晰度上限", selection: Binding(get: { playback.selectedQuality }, set: { playback.selectQuality($0) })) {
                        Text(playback.qualities.count > 1 ? "自动" : "原始 / 自动").tag("auto")
                        if playback.qualities.count > 1 { ForEach(playback.qualities) { Text($0.label).tag($0.id) } }
                    }.font(.caption).disabled(playback.qualities.count < 2)
                    Text(playback.qualities.count > 1 ? "按 HLS 提供的档位限制最高分辨率，仍可能随带宽降低，不是强制锁定。" : "当前媒体未提供多档 HLS 清晰度，将按原始画质播放。")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    if !playback.actualResolution.isEmpty { Text("当前画面  \(playback.actualResolution)").font(.caption).foregroundStyle(Theme.accent) }
                    Toggle("填满画面（可能裁切）", isOn: $playback.fillVideo).font(.caption)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    settingsHeading("播放引擎", icon: "play.desktopcomputer")
                    Text("内置 AVPlayer · 应用自定义控制栏").font(.caption).foregroundStyle(Theme.muted)
                    Button("交给外部 VLC") { playback.openVLC() }.buttonStyle(QuietButton()).disabled(playback.currentURL == nil || playback.vlcApplication == nil)
                    Text("VLC 可选，无需安装。外部播放不保证保留鉴权请求头。")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }.padding(.bottom, 14)
        }
    }
    private func settingsHeading(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
    }
    private func skipControl(_ title: String, value: Double, change: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            TextField(title, value: Binding(get: { value }, set: change), format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .font(.system(size: 12, design: .monospaced)).frame(width: 44)
                .padding(.horizontal, 8).frame(height: 30)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel(title + "秒数")
            Text("秒").font(.caption).foregroundStyle(Theme.muted)
            Stepper(title, value: Binding(get: { value }, set: change), in: 0...900, step: 5)
                .labelsHidden().fixedSize().accessibilityLabel(title)
        }
    }
    private func errorPanel(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(error).font(.caption).textSelection(.enabled).lineLimit(4)
            Spacer(minLength: 0)
            Button("重试") { playback.retryPlayback() }.buttonStyle(QuietButton())
        }.padding(16).background(Color.orange.opacity(0.06))
    }
}
