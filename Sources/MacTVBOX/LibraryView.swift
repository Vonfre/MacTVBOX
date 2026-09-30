import SwiftUI
import MacTVBOXCore

struct LibraryView: View {
    let history: Bool
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var playback: PlayerController
    @State private var managing = false
    @State private var selected = Set<String>()
    @State private var confirmDeletion = false
    private var items: [SavedVideo] { history ? store.history : store.favorites }
    private var validSelection: Set<String> { selected.intersection(items.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(history ? "最近播放" : "我的收藏").font(.system(size: 28, weight: .semibold))
                    Text(history ? "接着上次的故事。卡片内滚动选集，观看进度留在本机。" : "你的私人片单，无需登录账号。")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if !items.isEmpty {
                    Button(managing ? "完成" : "批量管理") { managing.toggle(); selected.removeAll() }.buttonStyle(QuietButton())
                }
            }
            if managing {
                HStack(spacing: 12) {
                    Button(validSelection.count == items.count ? "取消全选" : "全选") {
                        selected = validSelection.count == items.count ? [] : Set(items.map(\.id))
                    }.buttonStyle(QuietButton())
                    Text("已选 \(validSelection.count) / \(items.count) 项").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button { confirmDeletion = true } label: { Label("删除所选", systemImage: "trash") }
                        .buttonStyle(QuietButton()).disabled(validSelection.isEmpty)
                }.padding(12).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if items.isEmpty {
                ContentUnavailable(icon: history ? "clock" : "heart", title: history ? "还没有播放记录" : "还没有收藏",
                                   message: history ? "开始播放一部影片，观看进度会自动记录。" : "在影片详情中收藏喜欢的内容。")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(items) { saved in
                        LibraryCard(saved: saved, history: history, managing: managing, selected: validSelection.contains(saved.id),
                                    toggle: { if !selected.insert(saved.id).inserted { selected.remove(saved.id) } },
                                    open: { open(saved, episode: saved.episode) },
                                    playEpisode: { open(saved, episode: $0) })
                    }
                }
            }
        }
        .alert("删除所选的 \(validSelection.count) 条\(history ? "播放记录" : "收藏")？", isPresented: $confirmDeletion) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                store.removeLibraryItems(validSelection, history: history)
                selected.removeAll(); if items.isEmpty { managing = false }
            }
        } message: {
            Text(history ? "只删除本机播放记录和续播进度，不删除视频或收藏。正在播放的记录不会立即重新出现；再次主动播放后才会记录。此操作无法撤销。" : "只从本机收藏中移除，不影响播放记录或视频。此操作无法撤销。")
        }
    }
    private func open(_ saved: SavedVideo, episode: Episode?) {
        if history, let episode {
            let source = store.sources.first { $0.key == saved.source.key && $0.api == saved.source.api } ?? saved.source
            playback.play(video: saved.video, source: source, episode: episode,
                          line: saved.video.lines.first { $0.episodes.contains(episode) }, store: store)
            playback.present()
        } else { store.showDetail(saved.video, source: saved.source) }
    }
}

private struct LibraryCard: View {
    let saved: SavedVideo
    let history: Bool
    let managing: Bool
    let selected: Bool
    let toggle: () -> Void
    let open: () -> Void
    let playEpisode: (Episode) -> Void
    private var episodes: [Episode] {
        guard let current = saved.episode else { return [] }
        return saved.video.lines.first { $0.episodes.contains(current) }?.episodes ?? [current]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: managing ? toggle : open) {
                HStack(alignment: .top, spacing: 14) {
                    Poster(video: saved.video).frame(width: 76, height: 108).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 9) {
                        Text(saved.video.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).help(saved.video.title)
                        Text(saved.source.name).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer(minLength: 0)
                        Label(managing ? (selected ? "已选择" : "选择此项") : (history ? "继续播放" : "查看详情"),
                              systemImage: managing ? (selected ? "checkmark.circle.fill" : "circle") : "play.circle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    }.frame(height: 108, alignment: .topLeading)
                    Spacer(minLength: 0)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(SurfaceButton(selected: selected, restingOpacity: 0))
            if history {
                VStack(alignment: .leading, spacing: 6) {
                    Text("上次看到 · \(saved.progressText)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    Text(saved.episode?.name ?? "尚无集数").font(.system(size: 12)).lineLimit(2).help(saved.episode?.name ?? "")
                }.padding(.horizontal, 16).frame(height: 58, alignment: .topLeading)
                Divider().overlay(Color.white.opacity(0.04)).padding(.horizontal, 16)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(saved.video.title).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        if history {
                            ForEach(episodes) { episode in
                                Button { playEpisode(episode) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: episode.id == saved.episode?.id ? "play.fill" : "play")
                                        Text(episode.name).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                        if episode.id == saved.episode?.id { Text("上次").foregroundStyle(Theme.accent) }
                                    }.font(.system(size: 11)).padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(SurfaceButton(selected: episode.id == saved.episode?.id))
                                    .disabled(managing).id(episode.id)
                            }
                        } else {
                            Text(saved.video.summary.isEmpty ? saved.video.metadata : saved.video.summary)
                                .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(12)
                }.frame(height: history ? 128 : 106)
                    .onAppear { if let id = saved.episode?.id { proxy.scrollTo(id, anchor: .center) } }
                // Do not reset scrolling on each five-second playback progress update.
            }
            HStack {
                Text(saved.updatedAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                if history { Label("\(episodes.count) 集 · 内滚动", systemImage: "scroll") }
            }.font(.system(size: 9)).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 14)
        }.background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.accent.opacity(0.65) : Color.white.opacity(0.06), lineWidth: 1))
    }
}
