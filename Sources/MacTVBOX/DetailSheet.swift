import SwiftUI
import MacTVBOXCore

struct DetailSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var playback: PlayerController
    @State private var selectedLine = 0
    private var exactSourceGroups: [[SourceMatch]] {
        let matches = store.sortedDetailMatches.filter { TitleMatcher.confidence($0.video, for: store.detailAnchor ?? $0.video) >= 2 }
        return Dictionary(grouping: matches, by: { $0.source.key }).sorted { $0.key < $1.key }.map(\.value)
    }
    private var otherMatches: [SourceMatch] {
        store.sortedDetailMatches.filter { TitleMatcher.confidence($0.video, for: store.detailAnchor ?? $0.video) < 2 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("影片与播放来源").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Button { store.closeDetail() } label: { Image(systemName: "xmark") }.buttonStyle(IconButton()).keyboardShortcut(.cancelAction).accessibilityLabel("关闭影片详情")
            }.padding(24)
            ScrollViewReader { scroll in
            ScrollView {
                if let anchor = store.detailAnchor, let video = store.detailVideo {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 24) {
                            Poster(video: anchor).frame(width: 115, height: 162).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 12) {
                                Text(anchor.title).font(.system(size: 27, weight: .bold)).textSelection(.enabled)
                                Text(anchor.metadata).font(.caption).foregroundStyle(Theme.muted)
                                if !anchor.actors.isEmpty { Text("主演：" + anchor.actors).font(.caption).foregroundStyle(Theme.muted).lineLimit(2) }
                                if !anchor.remarks.isEmpty { Text(anchor.remarks).font(.caption).foregroundStyle(Theme.accent) }
                                if let url = store.detailSubjectURL { Link("在榜单网站查看剧情、评分与演职员 ↗", destination: url).font(.caption) }
                                Text("选择下方匹配来源后加载线路和剧集。搜索命中不代表播放已验证；同名作品请核对年份与主演。")
                                    .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                if let source = store.detailSource {
                                    Button { store.toggleFavorite(video, source: source) } label: {
                                        Label(store.isFavorite(video, source: source) ? "已收藏此版本" : "收藏此版本", systemImage: store.isFavorite(video, source: source) ? "heart.fill" : "heart")
                                    }.buttonStyle(QuietButton())
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        sourceMatches(anchor)
                        if let source = store.detailSource {
                            Divider().id("playback-options")
                            HStack {
                                Text("\(source.name) · \(video.title)").font(.headline)
                                Spacer()
                                Text(video.metadata).font(.caption).foregroundStyle(Theme.muted)
                            }
                            if !video.actors.isEmpty { Text("主演：\(video.actors)").font(.caption).foregroundStyle(Theme.muted) }
                            if !video.summary.isEmpty { Text(video.summary).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(6).textSelection(.enabled) }
                            if store.detailLoading { ProgressView("正在获取线路与选集…") }
                            if let error = store.detailError {
                                Text(error).font(.caption).foregroundStyle(.orange)
                                Button("重试此来源") { store.selectMatch(SourceMatch(video: video, source: source)) }.buttonStyle(QuietButton())
                            }
                            if !store.detailLoading && !video.lines.isEmpty { episodes(video, source: source) }
                            else if !store.detailLoading && store.detailError == nil {
                                Text("该记录没有提供播放线路，请尝试其他匹配来源。").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }.padding(.horizontal, 26).padding(.bottom, 30)
                }
            }
            .onChange(of: store.detailLoading) { loading in
                if !loading && store.detailSource != nil { withAnimation { scroll.scrollTo("playback-options", anchor: .top) } }
            }
            }
        }
        .frame(width: 850, height: 740).background(Theme.background).preferredColorScheme(.dark)
        .onAppear { selectedLine = store.detailVideo?.preferredLineIndex ?? 0 }
        .onChange(of: store.detailSource?.id) { _ in selectedLine = store.detailVideo?.preferredLineIndex ?? 0 }
        .onChange(of: store.detailVideo?.id) { _ in selectedLine = store.detailVideo?.preferredLineIndex ?? 0 }
        .onChange(of: store.detailVideo?.lines) { _ in selectedLine = store.detailVideo?.preferredLineIndex ?? 0 }
    }
    private func sourceMatches(_ anchor: Video) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("查找这部影片的片源").font(.headline)
                Spacer()
                if store.isMatching { ProgressView().controlSize(.small) }
                Text("已检查 \(store.matchingCompleted)/\(store.matchingTotal)").font(.caption).foregroundStyle(Theme.muted)
                Button("重新查找") { store.showTitle(anchor, subjectURL: store.detailSubjectURL) }.buttonStyle(QuietButton()).disabled(store.isMatching)
            }
            Text("仅搜索当前已适配协议；\(store.sources.count - store.supportedSources.count) 个需额外运行时的片源尚未检索。每个片源取第一页。")
                .font(.caption2).foregroundStyle(Theme.muted)
            ForEach(exactSourceGroups, id: \.first!.source.id) { matches in
                let active = matches.first { $0.source.id == store.detailSource?.id && $0.video.id == store.detailVideo?.id } ?? matches[0]
                HStack(spacing: 10) {
                    matchButton(active, anchor: anchor)
                    if matches.count > 1 {
                        Menu("其他 \(matches.count - 1) 个版本") {
                            ForEach(matches) { match in
                                Button("\(match.video.title) · \(match.video.year) · \(match.video.remarks) [\(match.video.id)]") { store.selectMatch(match) }
                            }
                        }.frame(width: 120)
                    }
                }
            }
            if !otherMatches.isEmpty {
                DisclosureGroup("\(otherMatches.count) 条近似片名 / 不同年份结果（需手动核对）") {
                    ForEach(otherMatches) { match in matchButton(match, anchor: anchor) }
                }.font(.caption)
            }
            if store.detailMatches.isEmpty {
                Text(store.isMatching ? "正在按片名检索，可在结果出现后直接选择，不必等待全部完成。" : "已响应的片源暂无匹配记录。可尝试搜索别名；失败的片源未能检查。")
                    .font(.caption).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            if !store.matchingFailures.isEmpty {
                DisclosureGroup("\(store.matchingFailures.count) 个片源未能检查") {
                    ForEach(store.matchingFailures, id: \.self) { Text($0).font(.caption2).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) }
                }
            }
        }
    }
    private func matchButton(_ match: SourceMatch, anchor: Video) -> some View {
        Button { store.selectMatch(match) } label: {
            HStack(spacing: 14) {
                Image(systemName: store.detailSource?.id == match.source.id && store.detailVideo?.id == match.video.id ? "checkmark.circle.fill" : "play.rectangle").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(match.source.name + " · " + match.video.title).font(.system(size: 12, weight: .semibold))
                    Text([match.video.year, match.video.remarks, TitleMatcher.matchLabel(match.video, for: anchor)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer()
                Text("查看线路 →").font(.caption).foregroundStyle(Theme.accent)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(SurfaceButton(selected: store.detailSource?.id == match.source.id && store.detailVideo?.id == match.video.id))
    }
    private func episodes(_ video: Video, source: Source) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("选集播放").font(.headline)
                Spacer()
                Picker("线路", selection: $selectedLine) {
                    ForEach(Array(video.lines.enumerated()), id: \.offset) { index, line in Text(line.name).tag(index) }
                }.frame(width: 250)
            }
            let line = video.lines[min(max(0, selectedLine), video.lines.count - 1)]
            if line.name.contains("限") || line.name.uppercased().contains("VIP") {
                Label("该线路可能限制次数或权限，也可能返回提示视频。应用不会绕过验证；可选择其他来源或线路。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                ForEach(line.episodes) { episode in
                    Button {
                        playback.play(video: video, source: source, episode: episode, line: line, store: store)
                        store.closeDetail(); playback.present()
                    } label: {
                        Text(episode.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(SurfaceButton())
                }
            }
            Text("默认使用内置 AVPlayer，无需安装 VLC。第三方片源可能含广告、失效链接或访问限制。")
                .font(.caption2).foregroundStyle(Theme.muted)
        }
    }
}
