import Foundation

/// Independent native client for the public Bili HTTP protocol. No Android code is executed.
public struct BiliSpiderProvider {
    let client: TVClient
    let source: Source
    let apiBase: String
    static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"
    public init(client: TVClient = TVClient(), source: Source) {
        self.client = client; self.source = source; self.apiBase = "https://api.bilibili.com"
    }
    // Test-only dependency seam, never derived from untrusted source.ext.
    init(client: TVClient, source: Source, apiBase: String) {
        self.client = client; self.source = source; self.apiBase = apiBase
    }
    private var options: [String: JSONValue] { Self.options(for: source) }
    static func options(for source: Source) -> [String: JSONValue] {
        if case .object(let values) = source.ext { return values }
        if let text = source.ext?.string, let data = text.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let values) = value { return values }
        return [:]
    }
    private func request(_ path: String, _ parameters: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: try URLTools.apiURL(apiBase + path, parameters: parameters))
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        if let cookie = options["cookie"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !cookie.isEmpty {
            guard !cookie.hasPrefix("http"), cookie.utf8.count <= 8192,
                  !cookie.contains("\r"), !cookie.contains("\n") else {
                throw SpiderFailure.configuration("B站 Cookie 必须为合法的本地配置值；不会自动下载远程 Cookie 文件。")
            }
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await client.fetch(request, limit: 6 * 1024 * 1024)
        return try Self.response(data)
    }
    static func response(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? Int else { throw SpiderFailure.format("B站响应缺少状态码。") }
        guard code == 0 else {
            let text = "B站 \(code)：\(root["message"] as? String ?? "请求失败")"
            if [-101, -111, -403, -412, -352, 61000, 62002].contains(code) { throw SpiderFailure.authentication(text + "。请在官方站点确认登录或验证，不会尝试绕过。") }
            throw SpiderFailure.upstream(text)
        }
        guard let payload = root["data"] as? [String: Any] else { throw SpiderFailure.format("B站响应缺少 data。") }
        return payload
    }
    public func browse(category: String? = nil, page: Int = 1, query: String? = nil) async throws -> VideoPage {
        let page = max(1, page)
        if let keyword = query ?? category, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard keyword != "peizhi", !keyword.contains("/{pg}") else {
                throw SpiderFailure.configuration("这个分类是 Android 登录工具或 UP 主专用规则；当前原生插件支持关键词分类和公开视频搜索。")
            }
            let payload = try await request("/x/web-interface/search/type", ["search_type": "video", "keyword": keyword, "page": String(page), "order": "totalrank"])
            return try Self.parseList(payload, key: "result", page: page)
        }
        let payload = try await request("/x/web-interface/popular", ["ps": "20", "pn": String(page)])
        var result = try Self.parseList(payload, key: "list", page: page)
        // Broken optional classification metadata must not disable searching and video playback.
        if let address = options["json"]?.string {
            do {
                let (data, _) = try await client.fetch(URLTools.httpURL(address), limit: 2 * 1024 * 1024)
                result.categories = try Self.parseCategories(data)
            } catch is CancellationError { throw CancellationError() }
            catch { result.categories = [Category(id: "公开课", name: "公开课"), Category(id: "纪录片", name: "纪录片")] }
        } else if let types = options["type"]?.string {
            result.categories = types.split(separator: "#").map { Category(id: String($0), name: String($0)) }
        }
        return result
    }
    static func parseCategories(_ data: Data) throws -> [Category] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["class"] as? [[String: Any]] else { throw SpiderFailure.format("B站分类不是 class 列表。") }
        var seen = Set<String>()
        return entries.compactMap { item in
            let id = ConfigurationParser.scalar(item["type_id"]), name = ConfigurationParser.scalar(item["type_name"])
            guard !id.isEmpty, !name.isEmpty, id != "peizhi", !id.contains("/{pg}"), seen.insert(id).inserted else { return nil }
            return Category(id: id, name: name)
        }
    }
    static func parseList(_ payload: [String: Any], key: String, page: Int) throws -> VideoPage {
        guard let rows = payload[key] as? [[String: Any]] else { throw SpiderFailure.format("B站缺少视频列表 \(key)。") }
        var seen = Set<String>()
        let videos: [Video] = rows.compactMap { row in
            let aid = ConfigurationParser.scalar(row["aid"])
            let bvid = ConfigurationParser.scalar(row["bvid"])
            let id = !aid.isEmpty ? aid : bvid
            guard validID(id), seen.insert(id).inserted,
                  let title = row["title"] as? String, !title.isEmpty else { return nil }
            let owner = row["owner"] as? [String: Any]
            return Video(id: id, title: VODParser.cleanText(title.replacingOccurrences(of: "</?em\\b[^>]*>", with: "", options: .regularExpression)), poster: URLTools.resolved(ConfigurationParser.scalar(row["pic"]), relativeTo: URL(string: "https://www.bilibili.com")),
                         remarks: ConfigurationParser.scalar(row["duration"]), genre: ConfigurationParser.scalar(row["typename"] ?? row["tname"]),
                         director: ConfigurationParser.scalar(row["author"] ?? owner?["name"]), summary: VODParser.cleanText(ConfigurationParser.scalar(row["description"] ?? row["desc"])))
        }
        guard rows.isEmpty || !videos.isEmpty else { throw SpiderFailure.format("B站列表没有可识别的视频，不能当成搜索无结果。") }
        let pages = payload["numPages"] as? Int ?? (videos.isEmpty || payload["no_more"] as? Bool == true ? page : page + 1)
        return VideoPage(videos: videos, page: page, pageCount: max(page, pages))
    }
    static func validID(_ value: String) -> Bool {
        value.range(of: #"^(?:[1-9][0-9]{0,19}|BV[0-9A-Za-z]{10})$"#, options: .regularExpression) != nil
    }
    public func detail(id: String) async throws -> Video {
        guard Self.validID(id) else { throw SpiderFailure.configuration("无效的 B站视频 ID。") }
        let payload = try await request("/x/web-interface/view", [id.hasPrefix("BV") ? "bvid" : "aid": id])
        return try Self.parseDetail(payload, requestedID: id)
    }
    static func parseDetail(_ payload: [String: Any], requestedID: String) throws -> Video {
        let aid = ConfigurationParser.scalar(payload["aid"]), bvid = ConfigurationParser.scalar(payload["bvid"])
        guard requestedID == aid || requestedID == bvid, validID(aid),
              let title = payload["title"] as? String, let pages = payload["pages"] as? [[String: Any]] else { throw SpiderFailure.format("B站详情与请求 ID 不匹配或缺少分P。") }
        let episodes: [Episode] = pages.compactMap { part in
            let cid = ConfigurationParser.scalar(part["cid"])
            guard validID(cid), !cid.hasPrefix("BV") else { return nil }
            return Episode(name: ConfigurationParser.scalar(part["part"]), address: aid + ":" + cid,
                           resolution: EpisodeResolution(parser: "bili", parseType: "native-bili", token: "", headers: [:]))
        }
        guard !episodes.isEmpty else { throw SpiderFailure.player("该 B站视频没有可用分P。") }
        return Video(id: requestedID, title: VODParser.cleanText(title.replacingOccurrences(of: "</?em\\b[^>]*>", with: "", options: .regularExpression)), poster: URLTools.resolved(ConfigurationParser.scalar(payload["pic"]), relativeTo: URL(string: "https://www.bilibili.com")),
                     summary: ConfigurationParser.scalar(payload["desc"]), lines: [PlayLine(name: "B站 · 公开 MP4", episodes: episodes)])
    }
    public func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        let ids = episode.address.split(separator: ":").map(String.init)
        guard episode.resolution?.parseType == "native-bili", ids.count == 2,
              ids.allSatisfy({ Self.validID($0) && !$0.hasPrefix("BV") }) else { throw SpiderFailure.player("缺少 B站分P信息，请重新打开详情。") }
        let payload = try await request("/x/player/playurl", ["avid": ids[0], "cid": ids[1], "qn": "16", "fnval": "1", "platform": "html5", "high_quality": "1"])
        return try Self.parsePlayer(payload)
    }
    static func parsePlayer(_ payload: [String: Any]) throws -> ResolvedMedia {
        guard let segments = payload["durl"] as? [[String: Any]], segments.count == 1,
              let address = segments.first?["url"] as? String else { throw SpiderFailure.player("B站没有返回单文件 MP4；DASH 音画分离、多段视频或会员限制暂不伪装成可播放直链。") }
        let url = try URLTools.httpURL(address)
        guard url.pathExtension.lowercased() == "mp4", !(payload["format"] as? String ?? "").lowercased().contains("flv") else {
            throw SpiderFailure.player("B站返回的不是原生播放器可用的 MP4。")
        }
        // Do not forward API Cookie to CDN or persist it in history.
        return ResolvedMedia(url: url, headers: ["User-Agent": agent, "Referer": "https://www.bilibili.com/"])
    }
}
