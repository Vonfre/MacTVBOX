import SwiftUI
import MacTVBOXCore

struct DiscoverView: View {
    @EnvironmentObject var store: AppStore
    private let columns = [GridItem(.adaptive(minimum: 158, maximum: 220), spacing: 18, alignment: .top)]
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.submittedQuery.isEmpty ? "发现好片" : "搜索影片")
                        .font(.system(size: 28, weight: .semibold))
                    Text("找到想看的，再选择播放来源。")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { store.submittedQuery.isEmpty ? store.browse() : store.search() } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(IconButton(size: 38)).help("刷新榜单 / 搜索").accessibilityLabel("刷新榜单或搜索")
            }.padding(.top, 4)
            if !store.submittedQuery.isEmpty { searchResults } else { rankings }
        }
    }
    private var rankings: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                ForEach(RankingProvider.allCases) { provider in
                    Button { store.selectRankingProvider(provider) } label: {
                        Text(provider.title).font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 22).padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(SurfaceButton(selected: store.rankingProvider == provider))
                }
                Spacer()
                Text(store.rankingProvider == .douban ? "十分制评分" : "影评人新鲜度 · %")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 6) {
                filter("为你发现", id: "all")
                ForEach(store.rankingCategories) { category in filter(category.title, id: category.id) }
                Spacer(minLength: 0)
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            ForEach(store.rankingCategories.filter { store.rankingFilter == "all" || store.rankingFilter == $0.id }) { category in
                rankingSection(category)
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                Text(store.rankingProvider == .douban ? "推荐来自豆瓣公开片单，保留来源顺序，并非全网播放量排名。上榜不代表已有可播放资源。" : "推荐来自 Rotten Tomatoes 公开热门片单。新鲜度是影评人好评比例，并非十分制评分；英文片名可能需要用中文译名搜索片源。")
            }.font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4).padding(.top, 4)
        }
    }
    private func rankingSection(_ category: RankingCategory) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(category.title).font(.system(size: 18, weight: .semibold))
                    if let result = store.rankingResults.first(where: { $0.id == category.id }) {
                        Text("\(category.provider.title)片单 · \(result.fetchedAt.formatted(date: .omitted, time: .shortened)) 更新")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                            .help("获取于 \(result.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                Spacer()
                Link(destination: category.pageURL) {
                    Label("来源", systemImage: "arrow.up.right").font(.system(size: 11))
                        .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Theme.muted).help("查看原始片单")
                if store.rankingFilter == "all" {
                    Button { store.rankingFilter = category.id } label: {
                        HStack(spacing: 6) { Text("查看全部"); Image(systemName: "chevron.right").font(.system(size: 9)) }
                    }.buttonStyle(QuietButton())
                }
            }
            if let result = store.rankingResults.first(where: { $0.id == category.id }) {
                if store.rankingFailures[category.id] != nil {
                    Label("更新失败，正在展示上次结果", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.orange)
                }
                if result.items.isEmpty { Text("来源暂未返回内容").foregroundStyle(Theme.muted) }
                if store.rankingFilter == "all" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(result.items) { item in
                                VideoCard(video: item.video) { store.showTitle(item.video, subjectURL: item.subjectURL) }.frame(width: 164)
                            }
                        }.padding(2)
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(result.items) { item in
                            VideoCard(video: item.video) { store.showTitle(item.video, subjectURL: item.subjectURL) }
                        }
                    }
                }
            } else if store.isLoading {
                ProgressView("正在读取片单…").frame(maxWidth: .infinity, minHeight: 160)
            }
            if let failure = store.rankingFailures[category.id] {
                Text(failure + " 可使用顶部搜索栏查找影片。").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(store.submittedQuery)”").font(.system(size: 20, weight: .semibold))
                    Text("\(store.titleGroups.count) 部影片 · \(store.searchHits.count) 条来源记录")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Button("返回推荐") { store.query = ""; store.submittedQuery = ""; store.browse() }.buttonStyle(QuietButton())
            }
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(store.titleGroups) { group in
                    VideoCard(video: group.video, subtitle: "\(group.sourceCount) 个匹配片源 · 待验证播放") {
                        store.showTitle(group.video, matches: group.matches)
                    }
                }
            }
            if !store.isLoading && store.searchHits.isEmpty {
                ContentUnavailable(icon: "magnifyingglass", title: "没有找到影片", message: "尝试缩短片名；请求失败不等于片源没有这部影片。")
            }
            if !store.searchFailures.isEmpty {
                DisclosureGroup("\(store.searchFailures.count) 个片源请求失败") {
                    ForEach(store.searchFailures, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }
                }
            }
            Text("搜索已适配来源的第一页；相同片名与年份合并展示，不同版本请在详情中核对。")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
    private func filter(_ title: String, id: String) -> some View {
        Button { store.rankingFilter = id } label: {
            Text(title).font(.system(size: 12, weight: store.rankingFilter == id ? .semibold : .medium))
                .foregroundStyle(store.rankingFilter == id ? Theme.accent : Theme.muted)
                .padding(.horizontal, 16).frame(height: 40).contentShape(Rectangle())
        }.buttonStyle(SurfaceButton(selected: store.rankingFilter == id))
            .accessibilityAddTraits(store.rankingFilter == id ? .isSelected : [])
    }
}
