import SwiftUI
import MacTVBOXCore

/// An explicit, user-initiated protocol check; never plays or downloads a media body.
struct SourceDiagnosticsSheet: View {
    let source: Source
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var steps: [String] = []
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("插件接入诊断").font(.system(size: 23, weight: .semibold))
            Text(source.name + " · " + source.kindLabel).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(source.compatibilityNote).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            TextField("可选：输入片名，同时验证搜索", text: $keyword).textFieldStyle(.roundedBorder).disabled(running)
            Text("依次检查首页、搜索（填写时）、首条结果详情和第一集解析。不自动播放，也不将解析成功当作实际播放成功。")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, message in
                        Text(message).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if steps.isEmpty { Text("点击开始检测，查看失败发生在哪一步。").foregroundStyle(Theme.muted).font(.system(size: 12)) }
                }.padding(15)
            }.frame(height: 230).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button(running ? "停止检测" : "关闭") {
                    if running { stop() } else { dismiss() }
                }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("开始检测") { start() }.buttonStyle(PrimaryButton()).disabled(running || !source.isSupported)
            }
        }.padding(30).frame(width: 620).background(Theme.background).preferredColorScheme(.dark)
            .onDisappear { task?.cancel(); generation = UUID() }
    }
    private func stop() {
        task?.cancel(); generation = UUID(); running = false
        steps.append("已停止；尚未完成的步骤不代表通过。")
    }
    private func start() {
        task?.cancel(); steps = []; running = true
        let run = UUID(); generation = run
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task { @MainActor in
            let client = TVClient()
            var stage = "首页"
            do {
                var page = try await client.browse(source: source)
                try Task.checkCancellation()
                guard generation == run else { return }
                steps.append("✓ 首页：\(page.categories.count) 个分类、\(page.videos.count) 条内容")
                if !query.isEmpty {
                    if source.searchable {
                        stage = "搜索"
                        page = try await client.browse(source: source, query: query)
                        try Task.checkCancellation()
                        guard generation == run else { return }
                        steps.append("✓ 搜索：\(page.videos.count) 条结果")
                    } else { steps.append("— 搜索：订阅声明不支持搜索，已跳过") }
                }
                if let first = page.videos.first {
                    stage = "详情"
                    let video = try await client.detail(source: source, id: first.id)
                    try Task.checkCancellation()
                    guard generation == run else { return }
                    steps.append("✓ 详情：\(video.title)，\(video.lines.count) 条线路")
                    if let episode = video.lines.first?.episodes.first {
                        stage = "播放解析"
                        let media = try await client.resolve(source: source, episode: episode)
                        try Task.checkCancellation()
                        guard generation == run else { return }
                        steps.append("✓ 解析：\(media.url.pathExtension.uppercased()) 媒体地址（尚未验证实际播放）")
                    } else { steps.append("— 未返回剧集，无法验证播放解析") }
                } else { steps.append("— 没有内容，未验证详情与播放解析") }
            } catch {
                guard !Task.isCancelled, generation == run else { return }
                steps.append("✕ \(stage)：\(error.localizedDescription)")
            }
            guard generation == run else { return }
            running = false
        }
    }
}
