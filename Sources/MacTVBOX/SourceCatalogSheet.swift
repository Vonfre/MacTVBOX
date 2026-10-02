import SwiftUI
import MacTVBOXCore

/// Optional catalog for specialty sources and upstreams whose search is unavailable.
/// The main discovery flow remains title-first; this sheet does not change a global source selection.
struct SourceCatalogSheet: View {
    let source: Source
    let onSelect: (Video) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [MacTVBOXCore.Category] = []
    @State private var category: String?
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var videos: [Video] = []
    @State private var page = 1
    @State private var pageCount = 1
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var revision = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.name).font(.system(size: 23, weight: .semibold))
                    Text(source.kindLabel).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
            }
            Text(source.compatibilityNote).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if source.searchable {
                HStack {
                    TextField("搜索此来源…", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                    Button("搜索") { search() }.buttonStyle(QuietButton())
                    if !submittedQuery.isEmpty {
                        Button("返回目录") { query = ""; submittedQuery = ""; load() }.buttonStyle(QuietButton())
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton("首页", id: nil)
                    ForEach(categories) { categoryButton($0.name, id: $0.id) }
                }
            }
            if loading { HStack { ProgressView().controlSize(.small); Text("正在读取目录…").font(.callout).foregroundStyle(Theme.muted) } }
            if let error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer()
                    Button("重试") { load(page: page) }.buttonStyle(QuietButton())
                }
            }
            ScrollView {
                if videos.isEmpty && !loading && error == nil {
                    Text(categories.isEmpty ? "此目录没有返回内容。" : "首页暂无推荐，可点击上方分类浏览。").foregroundStyle(Theme.muted).padding(30)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 18)], spacing: 22) {
                    ForEach(videos) { video in
                        VideoCard(video: video) { onSelect(video); dismiss() }
                    }
                }
            }
            HStack {
                Text("目录可见不等于每条线路可播，播放时仍会校验。").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Button("上一页") { load(page: page - 1) }.buttonStyle(QuietButton()).disabled(loading || error != nil || page <= 1)
                Text("\(page) / \(pageCount)").font(.system(size: 11)).monospacedDigit()
                Button("下一页") { load(page: page + 1) }.buttonStyle(QuietButton()).disabled(loading || error != nil || page >= pageCount)
            }
        }.padding(26).frame(width: 820, height: 680).background(Theme.background).preferredColorScheme(.dark)
            .onAppear { load() }
            .onDisappear { task?.cancel(); revision = UUID() }
    }
    private func categoryButton(_ name: String, id: String?) -> some View {
        Button {
            category = id; submittedQuery = ""; query = ""; load()
        } label: {
            Text(name).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(category == id && submittedQuery.isEmpty ? Theme.accent : Theme.muted)
                .background(category == id && submittedQuery.isEmpty ? Theme.accent.opacity(0.12) : Theme.panel)
                .clipShape(Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain)
    }
    private func search() { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines); load() }
    private func load(page requestedPage: Int = 1) {
        task?.cancel(); let run = UUID(); revision = run
        loading = true; error = nil; videos = []; page = max(1, requestedPage); pageCount = page
        let chosen = category, keyword = submittedQuery, requested = page
        task = Task { @MainActor in
            do {
                let result = try await TVClient().browse(source: source, category: chosen, page: requested, query: keyword.isEmpty ? nil : keyword)
                guard !Task.isCancelled, revision == run else { return }
                videos = result.videos; pageCount = max(requested, result.pageCount)
                if !result.categories.isEmpty { categories = result.categories }
            } catch {
                guard !Task.isCancelled, revision == run else { return }
                self.error = error.localizedDescription
            }
            guard revision == run else { return }; loading = false
        }
    }
}
