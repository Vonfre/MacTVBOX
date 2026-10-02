import Foundation

/// Native HTTP protocol implementation. No downloaded code, Java or Android runtime.
struct JianpianProvider {
    let client: TVClient
    let source: Source
    static let headers = ["User-Agent": "Mozilla/5.0", "X-Requested-With": "com.jp3.xg3", "Accept": "application/json, text/plain, */*"]
    private var base: URL {
        get throws {
            guard let ext = source.ext?.string else { throw SpiderFailure.configuration("荐片缺少 API 地址。") }
            let url = try URLTools.httpURL(ext)
            guard url.query == nil, url.fragment == nil else { throw SpiderFailure.configuration("荐片 API 地址不能包含查询或片段。") }
            return url
        }
    }
    private func request(_ path: String, _ parameters: [String: String] = [:], metadata: Bool = false) async throws -> [String: Any] {
        let url = try URLTools.apiURL(base.appendingPathComponent(path).absoluteString, parameters: parameters)
        var request = URLRequest(url: url); request.allHTTPHeaderFields = Self.headers
        if metadata { request.timeoutInterval = 6 }
        let (data, _) = try await client.fetch(request, limit: metadata ? 128 * 1024 : 12 * 1024 * 1024)
        return try Self.response(data)
    }
    static func response(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.format("荐片没有返回 JSON 对象。") }
        guard let code = json["code"] as? Int, [1, 200].contains(code) else {
            throw SpiderFailure.upstream("荐片请求失败：" + String((json["msg"] as? String ?? "未知状态").prefix(120)))
        }
        guard json["data"] != nil else { throw SpiderFailure.format("荐片响应缺少 data。") }
        return json
    }
    private func imageBase() async -> URL? {
        guard let base = try? base else { return nil }
        return await client.nativeMetadata.url(key: "jianpian:" + base.absoluteString) {
            // Optional metadata must never prevent searching or playback.
            guard let settings = try? await request("api/v2/settings/packageDomainConfig", metadata: true),
                  let data = settings["data"] as? [String: Any], let names = data["imgDomain"] as? String,
                  let first = names.split(separator: ",").first else { return nil }
            let text = first.trimmingCharacters(in: .whitespacesAndNewlines)
            return try? URLTools.httpURL(text.contains("://") ? text : "https://" + text)
        }
    }

    static func text(_ json: [String: Any], _ key: String) -> String {
        if let value = json[key] as? String { return value }
        if let value = json[key] as? NSNumber { return value.stringValue }
        return ""
    }
    static func video(_ json: [String: Any], imageBase: URL?, slide: Bool = false) throws -> Video {
        let id = text(json, slide ? "jump_id" : "id"), title = text(json, "title")
        guard id.range(of: "^[0-9]+$", options: .regularExpression) != nil, !title.isEmpty else { throw SpiderFailure.format("荐片条目缺少合法 ID 或标题。") }
        let path = text(json, "thumbnail").isEmpty ? text(json, "path") : text(json, "thumbnail")
        let poster = path.isEmpty ? "" : URLTools.resolved(path, relativeTo: imageBase)
        let playlist = json["playlist"] as? [String: Any] ?? [:]
        return Video(id: id, title: VODParser.cleanText(title), poster: (try? URLTools.httpURL(poster))?.absoluteString ?? "", remarks: text(json, "mask").isEmpty ? text(playlist, "title") : text(json, "mask"))
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let page = max(1, page)
        let json: [String: Any]
        var categories: [Category] = []
        let searching = !(query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if searching {
            json = try await request("api/v2/search/videoV2", ["key": query!.trimmingCharacters(in: .whitespacesAndNewlines), "category_id": "88", "page": String(page), "pageSize": "20"])
        } else if let category {
            guard category.range(of: "^[0-9]+$", options: .regularExpression) != nil else { throw SpiderFailure.configuration("荐片分类 ID 无效。") }
            if category == "99" { json = try await request("api/dyTag/list", ["category_id": category, "page": String(page)]) }
            else { json = try await request("api/crumb/list", ["fcate_pid": category, "area": "0", "year": "0", "type": "0", "sort": "0", "page": String(page), "category_id": ""]) }
        } else {
            let home = try await request("api/term/home_fenlei")
            guard let items = home["data"] as? [[String: Any]] else { throw SpiderFailure.format("荐片分类格式已变化。") }
            categories = items.compactMap { item in
                let id = Self.text(item, "id"), name = Self.text(item, "name")
                return name.isEmpty || name == "推荐" ? nil : Category(id: id, name: name)
            }
            json = try await request("api/slide/list", ["pos_id": "88"])
        }
        guard var items = json["data"] as? [[String: Any]] else { throw SpiderFailure.format("荐片列表格式已变化。") }
        if category == "99" { items = items.flatMap { $0["dataList"] as? [[String: Any]] ?? [] } }
        let images = await imageBase()
        try Task.checkCancellation()
        let videos = try items.map { try Self.video($0, imageBase: images, slide: !searching && category == nil) }
        let hasNext = (searching || category != nil && category != "99") && !items.isEmpty
        let total = json["total"] as? Int
        let pageCount = searching && total != nil ? max(page, (max(0, total!) + 19) / 20) : (hasNext ? page + 1 : page)
        return VideoPage(videos: videos, categories: categories, page: page, pageCount: pageCount)
    }
    func detail(id: String) async throws -> Video {
        guard id.range(of: "^[0-9]+$", options: .regularExpression) != nil else { throw SpiderFailure.configuration("荐片影片 ID 无效。") }
        let json = try await request("api/video/detailv2", ["id": id])
        guard let item = json["data"] as? [String: Any] else { throw SpiderFailure.format("荐片详情格式已变化。") }
        let result = try Self.detail(item, imageBase: await imageBase())
        guard result.id == id else { throw SpiderFailure.format("荐片返回了不同影片的详情。") }
        return result
    }
    static func detail(_ item: [String: Any], imageBase: URL?) throws -> Video {
        var result = try video(item, imageBase: imageBase)
        func names(_ key: String) -> String { (item[key] as? [[String: Any]] ?? []).map { text($0, "title").isEmpty ? text($0, "name") : text($0, "title") }.joined(separator: " / ") }
        result.year = text(item, "year"); result.area = text(item, "area"); result.genre = names("types")
        result.actors = names("actors"); result.director = names("directors"); result.summary = VODParser.cleanText(text(item, "description"))
        guard let groups = item["source_list_source"] as? [[String: Any]] else { throw SpiderFailure.format("荐片详情缺少播放线路。") }
        result.lines = groups.enumerated().compactMap { index, group in
            let episodes = (group["source_list"] as? [[String: Any]] ?? []).enumerated().compactMap { number, entry -> Episode? in
                let address = text(entry, "url")
                // Proprietary FTP/P2P and restricted routes are not falsely advertised as playable.
                guard let url = try? URLTools.httpURL(address), ["m3u8", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) else { return nil }
                let name = text(entry, "source_name")
                return Episode(name: name.isEmpty ? "第\(number + 1)集" : name, address: url.absoluteString, resolution: EpisodeResolution(parser: "jianpian", parseType: "native-jianpian", token: "", headers: [:]))
            }
            guard !episodes.isEmpty else { return nil }
            let name = text(group, "name")
            return PlayLine(name: name.isEmpty ? "线路\(index + 1)" : name, episodes: episodes)
        }
        guard !result.lines.isEmpty else { throw SpiderFailure.player("荐片没有可用的 HTTP 视频线路；专有 P2P、FTP 或受限线路暂不支持。") }
        return result
    }
    func resolve(_ episode: Episode) throws -> ResolvedMedia {
        let url = try URLTools.httpURL(episode.address)
        guard ["m3u8", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) else { throw SpiderFailure.player("荐片返回了不受支持的媒体格式。") }
        // Never forward stale bridge tokens or plugin-supplied arbitrary headers.
        return ResolvedMedia(url: url, headers: Self.headers)
    }
}
