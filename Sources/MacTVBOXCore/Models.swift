import Foundation

public enum TVError: LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

public struct Source: Codable, Identifiable, Hashable {
    public var key: String
    public var name: String
    public var type: Int
    public var api: String
    public var searchable: Bool
    public var ext: JSONValue?
    public var jar: String?
    /// Local, explicitly configured mapping; never read from a remote TVBox configuration.
    public var bridgeURL: String?
    public var usesHTTPSpider: Bool { (bridgeURL.flatMap { try? URLTools.httpURL($0) } != nil) || (type == 4 && (try? URLTools.httpURL(api)) != nil) }
    public var isAppGet: Bool { type == 3 && api == "csp_AppGet" && ext?.string != nil }
    public var id: String { key }
    public var isSupported: Bool { usesHTTPSpider || isAppGet || ((type == 0 || type == 1) && (try? URLTools.httpURL(api)) != nil) }
    public var kindLabel: String {
        if bridgeURL != nil { return "HTTP 运行时桥接" }
        switch type {
        case 0: return "XML 接口"
        case 1: return "JSON 接口"
        case 3: return isAppGet ? "AppGet 原生适配" : "Spider 插件"
        case 4: return "TVBox HTTP 接口"
        default: return "类型 \(type)"
        }
    }
    public var compatibilityNote: String {
        if usesHTTPSpider { return "已接入 HTTP 协议 · 执行与解析由你配置的服务端负责；未保证服务在线或插件兼容。" }
        if isAppGet { return "AppGet 协议已适配 · 支持分类、搜索、选集和解析；可用性取决于上游站点。" }
        if isSupported { return "原生支持 · 可浏览、搜索和选集" }
        switch type {
        case 3:
            if ["csp_Config", "csp_Push", "csp_Douban"].contains(api) { return "配置 / 推送 / 元数据入口，不是普通点播源。推荐请使用发现页。" }
            if ["csp_Duopan", "csp_MiSou", "csp_PanSearch"].contains(api) { return "网盘聚合插件：需要受信任运行时与合法网盘授权；不能直接当作媒体地址。" }
            if api.lowercased().contains(".js") { return "JS 规则：可连接部署了该规则的 HTTP 运行时；本机不直接执行远程 JS。" }
            return "Android Spider：需兼容 Android 环境执行并通过 HTTP 服务暴露；仅安装 Java 或 Node 不足以运行。"
        case 4: return "HTTP 运行时地址无效，请填写完整 HTTP / HTTPS 接口。"
        default: return "暂不支持此接口类型或地址格式。"
        }
    }
    public init(key: String, name: String, type: Int, api: String, searchable: Bool = true, ext: JSONValue? = nil, jar: String? = nil) {
        self.key = key; self.name = name; self.type = type; self.api = api; self.searchable = searchable; self.ext = ext; self.jar = jar
    }
}

public struct TVConfiguration: Codable {
    public var sources: [Source]
    public var spider: String?
    public var warnings: [String]
    public init(sources: [Source], spider: String? = nil, warnings: [String] = []) {
        self.sources = sources; self.spider = spider; self.warnings = warnings
    }
}

public struct Category: Identifiable, Hashable, Codable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Episode: Codable, Identifiable, Hashable {
    public var name: String
    public var address: String
    public var resolution: EpisodeResolution?
    public var id: String { name + "|" + address }
    public init(name: String, address: String, resolution: EpisodeResolution? = nil) { self.name = name; self.address = address; self.resolution = resolution }
    public var directURL: URL? { try? URLTools.httpURL(address) }
}

public struct PlayLine: Codable, Identifiable, Hashable {
    public var name: String
    public var episodes: [Episode]
    public var id: String { name }
    public init(name: String, episodes: [Episode]) { self.name = name; self.episodes = episodes }
}

public struct Video: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var poster: String
    public var remarks: String
    public var year: String
    public var area: String
    public var genre: String
    public var director: String
    public var actors: String
    public var summary: String
    public var lines: [PlayLine]
    public init(id: String, title: String, poster: String = "", remarks: String = "", year: String = "", area: String = "", genre: String = "", director: String = "", actors: String = "", summary: String = "", lines: [PlayLine] = []) {
        self.id = id; self.title = title; self.poster = poster; self.remarks = remarks
        self.year = year; self.area = area; self.genre = genre; self.director = director
        self.actors = actors; self.summary = summary; self.lines = lines
    }
    public var metadata: String { [year, area, genre].filter { !$0.isEmpty }.joined(separator: " · ") }
}

public struct RecommendationSection: Identifiable {
    public var id: String
    public var title: String
    public var videos: [Video]
}

public struct EpisodeResolution: Codable, Hashable {
    public var parser: String
    public var parseType: String
    public var token: String
    public var headers: [String: String]
}

public struct ResolvedMedia {
    public var url: URL
    public var headers: [String: String]
    public init(url: URL, headers: [String: String] = [:]) { self.url = url; self.headers = headers }
}

public struct VideoPage {
    public var recommendations: [RecommendationSection] = []
    public var videos: [Video]
    public var categories: [Category]
    public var page: Int
    public var pageCount: Int
    public init(videos: [Video], categories: [Category] = [], page: Int = 1, pageCount: Int = 1) {
        self.videos = videos; self.categories = categories; self.page = page; self.pageCount = pageCount
    }
}

public struct SavedVideo: Codable, Identifiable, Hashable {
    public var video: Video
    public var source: Source
    public var updatedAt: Date
    public var episode: Episode?
    public var position: Double
    public var id: String { source.key + "|" + source.api + "|" + video.id }
    public init(video: Video, source: Source, episode: Episode? = nil, position: Double = 0, updatedAt: Date = Date()) {
        self.video = video; self.source = source; self.episode = episode; self.position = position; self.updatedAt = updatedAt
    }
}
