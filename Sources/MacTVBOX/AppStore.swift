import SwiftUI
import MacTVBOXCore

struct LibrarySnapshot: Codable {
    var configuration: TVConfiguration?
    var configurationAddress: String
    var customSources: [Source]
    var selectedSourceID: String?
    var favorites: [SavedVideo]
    var history: [SavedVideo]
    var rankingProvider: RankingProvider?
    var bridgeBindings: [String: String]?
}

enum Section: String, CaseIterable, Identifiable {
    case discover = "发现", favorites = "我的收藏", history = "最近播放", sources = "片源管理"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .discover: return "square.grid.2x2"
        case .favorites: return "heart"
        case .history: return "clock.arrow.circlepath"
        case .sources: return "externaldrive.connected.to.line.below"
        }
    }
}

typealias SearchHit = SourceMatch

@MainActor final class AppStore: ObservableObject {
    @Published var section: Section = .discover
    @Published var configuration: TVConfiguration?
    @Published var configurationAddress = URLTools.defaultConfiguration
    @Published var customSources: [Source] = []
    @Published var bridgeBindings: [String: String] = [:]
    @Published var selectedSourceID: String?
    @Published var favorites: [SavedVideo] = []
    @Published var history: [SavedVideo] = []
    @Published var videos: [Video] = []
    @Published var recommendations: [RecommendationSection] = []
    @Published var searchHits: [SearchHit] = []
    @Published var searchFailures: [String] = []
    @Published var rankingResults: [RankingResult] = []
    @Published var rankingFailures: [String: String] = [:]
    @Published var rankingFilter = "all"
    @Published var rankingProvider: RankingProvider = .douban
    var rankingCategories: [RankingCategory] { rankingProvider.categories }
    @Published var detailAnchor: Video?
    @Published var detailMatches: [SourceMatch] = []
    @Published var matchingFailures: [String] = []
    @Published var matchingCompleted = 0
    @Published var matchingTotal = 0
    @Published var isMatching = false
    @Published var detailSubjectURL: URL?
    var titleGroups: [TitleGroup] {
        TitleMatcher.groups(searchHits).sorted {
            let a = TitleMatcher.relevance($0.video.title, query: submittedQuery)
            let b = TitleMatcher.relevance($1.video.title, query: submittedQuery)
            return a == b ? $0.id < $1.id : a > b
        }
    }
    var sortedDetailMatches: [SourceMatch] {
        detailMatches.sorted {
            let a = TitleMatcher.confidence($0.video, for: detailAnchor ?? $0.video)
            let b = TitleMatcher.confidence($1.video, for: detailAnchor ?? $1.video)
            return a == b ? $0.id < $1.id : a > b
        }
    }
    @Published var categories: [MacTVBOXCore.Category] = []
    @Published var categoryID: String?
    @Published var query = ""
    @Published var submittedQuery = ""
    @Published var page = 1
    @Published var pageCount = 1
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var error: String?
    @Published var info: String?
    @Published var detailVideo: Video?
    @Published var detailSource: Source?
    @Published var detailLoading = false
    @Published var detailError: String?
    @Published var showDirect = false
    @Published var showAddSource = false
    private var historyDeletionGuard = HistoryDeletionGuard()
    private let client = TVClient()
    private var browseTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var matchTask: Task<Void, Never>?
    private var matchRevision = UUID()
    private var browseRevision = UUID()
    private var detailRevision = UUID()
    private var persistenceURL: URL
    var sources: [Source] {
        (customSources + (configuration?.sources ?? [])).map { original in
            var source = original
            source.bridgeURL = bridgeBindings[source.key + "|" + source.api]
            return source
        }
    }
    var supportedSources: [Source] { sources.filter(\.isSupported) }
    var selectedSource: Source? { sources.first { $0.id == selectedSourceID } }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacTVBOX", isDirectory: true)
        persistenceURL = folder.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: persistenceURL.path) {
                let saved = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: persistenceURL))
                configuration = saved.configuration; configurationAddress = saved.configurationAddress
                customSources = saved.customSources; selectedSourceID = saved.selectedSourceID
                favorites = saved.favorites; history = saved.history
                rankingProvider = saved.rankingProvider ?? .douban
                bridgeBindings = saved.bridgeBindings ?? [:]
            }
        } catch { self.error = "读取本地资料失败，原文件未删除：\(error.localizedDescription)" }
    }
    func persist() {
        let snapshot = LibrarySnapshot(configuration: configuration, configurationAddress: configurationAddress, customSources: customSources, selectedSourceID: selectedSourceID, favorites: favorites, history: history, rankingProvider: rankingProvider, bridgeBindings: bridgeBindings)
        do { try JSONEncoder().encode(snapshot).write(to: persistenceURL, options: .atomic) }
        catch { self.error = "保存本地资料失败：\(error.localizedDescription)" }
    }
    func start() {
        browse()
        // v0.1 snapshots discarded ext. Refresh the existing subscription without losing user data.
        if configuration == nil || configuration?.sources.contains(where: { $0.api == "csp_AppGet" && $0.ext == nil }) == true {
            Task { await importConfiguration() }
        } else {
            if selectedSource?.isSupported != true { selectedSourceID = preferredSource?.id }
        }
    }
    var preferredSource: Source? {
        supportedSources.first(where: { $0.key == "一碗" }) ?? supportedSources.first
    }
    func importConfiguration() async {
        guard !isImporting else { return }
        isImporting = true; error = nil; info = nil
        defer { isImporting = false }
        let address = configurationAddress
        do {
            let config = try await client.configuration(at: address)
            configuration = config
            selectedSourceID = preferredSource?.id ?? sources.first?.id
            persist(); resetBrowse()
            info = "已导入 \(config.sources.count) 个源，其中 \(config.sources.filter(\.isSupported).count) 个已适配协议（不代表上游站点全部在线）。"
            browse()
        } catch { self.error = "导入失败（保留已有片源）：\(friendlyError(error))" }
    }
    func importFile(_ url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { throw TVError.message("配置文件超过 8 MB。") }
            let config = try ConfigurationParser.parse(Data(contentsOf: url))
            configuration = config; selectedSourceID = preferredSource?.id ?? sources.first?.id
            persist(); resetBrowse()
            info = "已从本地导入 \(config.sources.count) 个源。"
            browse()
        } catch { self.error = friendlyError(error) }
    }
    func addSource(name: String, address: String, type: Int) throws {
        let url = try URLTools.httpURL(address)
        guard !sources.contains(where: { $0.api == url.absoluteString && $0.type == type }) else { throw TVError.message("这个接口已经添加。") }
        let source = Source(key: "custom-\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? "自定义接口") : name, type: type, api: url.absoluteString)
        customSources.append(source); choose(source); section = .discover
    }
    func setBridge(_ endpoint: String?, for source: Source) throws {
        let key = source.key + "|" + source.api
        if let endpoint { bridgeBindings[key] = try URLTools.httpURL(endpoint).absoluteString }
        else { bridgeBindings.removeValue(forKey: key) }
        // Drop in-flight results which captured the previous runtime mapping.
        closeDetail(); resetBrowse(); persist(); browse()
    }
    func removeSource(_ source: Source) {
        bridgeBindings.removeValue(forKey: source.key + "|" + source.api)
        customSources.removeAll { $0.id == source.id }
        if selectedSourceID == source.id { selectedSourceID = preferredSource?.id ?? sources.first?.id; resetBrowse(); browse() }
        persist()
    }
    func choose(_ source: Source) {
        guard selectedSourceID != source.id else { return }
        info = nil
        selectedSourceID = source.id; query = ""; submittedQuery = ""; categoryID = nil
        resetBrowse(); persist(); browse()
    }
    func resetBrowse() {
        browseTask?.cancel(); browseRevision = UUID(); isLoading = false
        videos = []; recommendations = []; searchHits = []; searchFailures = []; categories = []; page = 1; pageCount = 1; categoryID = nil
        query = ""; submittedQuery = ""
    }
    func search() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        categoryID = nil
        if submittedQuery.isEmpty { browse(); return }
        browseTask?.cancel()
        let revision = UUID(); browseRevision = revision
        let keyword = submittedQuery
        let candidates = supportedSources.filter(\.searchable)
        searchHits = []; searchFailures = []; recommendations = []; videos = []; error = nil
        guard !candidates.isEmpty else { error = "没有已适配的可搜索片源，请先导入配置。"; isLoading = false; return }
        isLoading = true
        browseTask = Task {
            await withTaskGroup(of: (Source, [Video], String?).self) { group in
                var remaining = candidates.makeIterator()
                func enqueue(_ source: Source) {
                    group.addTask {
                        do { return (source, try await self.client.browse(source: source, query: keyword).videos, nil) }
                        catch { return (source, [], error.localizedDescription) }
                    }
                }
                for _ in 0..<3 { if let source = remaining.next() { enqueue(source) } }
                for await (source, items, failure) in group {
                    guard !Task.isCancelled, self.browseRevision == revision else { group.cancelAll(); return }
                    self.searchHits.append(contentsOf: items.map { SearchHit(video: $0, source: source) })
                    if let failure { self.searchFailures.append("\(source.name)：\(failure)") }
                    if let source = remaining.next() { enqueue(source) }
                }
            }
            if browseRevision == revision { isLoading = false }
        }
    }
    func selectRankingProvider(_ provider: RankingProvider) {
        guard rankingProvider != provider else { return }
        rankingProvider = provider; rankingFilter = "all"; persist(); browse()
    }
    func browse(page requestedPage: Int = 1) {
        if !submittedQuery.isEmpty { search(); return }
        browseTask?.cancel()
        let revision = UUID(); browseRevision = revision
        isLoading = true; error = nil
        searchHits = []; searchFailures = []; rankingFailures = [:]
        let requestedCategories = rankingCategories
        browseTask = Task {
            await withTaskGroup(of: (RankingCategory, RankingResult?, String?).self) { group in
                for category in requestedCategories {
                    group.addTask {
                        do { return (category, try await RankingClient().fetch(category), nil) }
                        catch { return (category, nil, error.localizedDescription) }
                    }
                }
                for await (category, result, failure) in group {
                    guard !Task.isCancelled, browseRevision == revision else { group.cancelAll(); return }
                    if let result {
                        rankingResults.removeAll { $0.id == category.id }
                        rankingResults.append(result)
                    }
                    if let failure { rankingFailures[category.id] = failure }
                }
            }
            if browseRevision == revision { isLoading = false }
        }
    }
    func showTitle(_ video: Video, matches: [SourceMatch] = [], subjectURL: URL? = nil) {
        closeDetail()
        detailAnchor = video; detailVideo = video; detailSubjectURL = subjectURL
        detailMatches = matches; matchingFailures = []; matchingCompleted = 0
        let candidates = supportedSources.filter(\.searchable)
        matchingTotal = candidates.count; isMatching = !candidates.isEmpty
        let revision = UUID(); matchRevision = revision
        matchTask = Task {
            await withTaskGroup(of: (Source, [Video], String?).self) { group in
                var remaining = candidates.makeIterator()
                func enqueue(_ source: Source) {
                    group.addTask {
                        do { return (source, try await self.client.browse(source: source, query: video.title).videos, nil) }
                        catch { return (source, [], error.localizedDescription) }
                    }
                }
                for _ in 0..<3 { if let source = remaining.next() { enqueue(source) } }
                for await (source, items, failure) in group {
                    guard !Task.isCancelled, matchRevision == revision else { group.cancelAll(); return }
                    matchingCompleted += 1
                    for item in items {
                        let match = SourceMatch(video: item, source: source)
                        if !detailMatches.contains(where: { $0.id == match.id }) { detailMatches.append(match) }
                    }
                    if let failure { matchingFailures.append("\(source.name)：\(failure)") }
                    if let source = remaining.next() { enqueue(source) }
                }
            }
            if matchRevision == revision { isMatching = false }
        }
    }
    func showDetail(_ video: Video, source: Source) {
        let current = sources.first(where: { $0.key == source.key && $0.api == source.api }) ?? source
        showTitle(video, matches: [SourceMatch(video: video, source: current)])
    }
    func selectMatch(_ match: SourceMatch) {
        detailTask?.cancel()
        let revision = UUID(); detailRevision = revision
        detailSource = match.source; detailVideo = match.video; detailError = nil
        guard match.source.isSupported else { detailLoading = false; detailError = match.source.compatibilityNote; return }
        detailLoading = true
        detailTask = Task {
            do {
                let full = try await client.detail(source: match.source, id: match.video.id)
                guard !Task.isCancelled, detailRevision == revision else { return }
                detailVideo = full
            } catch {
                guard !Task.isCancelled, detailRevision == revision else { return }
                detailError = friendlyError(error)
            }
            if detailRevision == revision { detailLoading = false }
        }
    }
    func closeDetail() {
        detailTask?.cancel(); matchTask?.cancel(); detailRevision = UUID(); matchRevision = UUID()
        detailVideo = nil; detailAnchor = nil; detailSource = nil; detailSubjectURL = nil
        detailMatches = []; detailLoading = false; detailError = nil; isMatching = false
    }
    func isFavorite(_ video: Video, source: Source) -> Bool { favorites.contains { $0.id == SavedVideo(video: video, source: source).id } }
    func toggleFavorite(_ video: Video, source: Source) {
        let saved = SavedVideo(video: video, source: source)
        if favorites.contains(where: { $0.id == saved.id }) { favorites.removeAll { $0.id == saved.id } }
        else { favorites.insert(saved, at: 0) }
        persist()
    }
    func removeLibraryItems(_ ids: Set<String>, history: Bool) {
        if history { self.history = historyDeletionGuard.delete(ids, from: self.history) }
        else { favorites.removeAll { ids.contains($0.id) } }
        persist()
    }
    func beginPlayback(video: Video, source: Source) {
        historyDeletionGuard.beginPlayback(id: SavedVideo(video: video, source: source).id)
    }
    func record(_ video: Video, source: Source, episode: Episode, position: Double) {
        let saved = SavedVideo(video: video, source: source, episode: episode, position: max(0, position.isFinite ? position : 0))
        guard historyDeletionGuard.allowsRecording(id: saved.id) else { return }
        history.removeAll { $0.id == saved.id }; history.insert(saved, at: 0)
        history = Array(history.prefix(100)); persist()
    }
    func resumePosition(video: Video, source: Source, episode: Episode) -> Double {
        history.first { $0.id == SavedVideo(video: video, source: source).id && $0.episode?.address == episode.address }?.position ?? 0
    }
    func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorSecureConnectionFailed:
                return "TLS / HTTPS 证书验证失败。为保护连接，应用不会忽略证书错误。"
            case NSURLErrorTimedOut: return "请求超时，请检查网络或更换片源。"
            case NSURLErrorNotConnectedToInternet: return "网络未连接。"
            default: break
            }
        }
        return error.localizedDescription
    }
}
