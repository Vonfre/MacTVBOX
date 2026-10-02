import Foundation

/// Native port of the current Jpys public website protocol, not the obsolete Android HTML selectors.
/// No remote JS execution, browser fingerprinting or account impersonation. Restricted qualities are excluded.
struct JpysSpiderProvider {
    let client: TVClient
    let source: Source
    static let publicProtocolKey = "cb808529bae6b6be45ecfab29a4889bc"
    static let categories = [Category(id: "1", name: "电影"), Category(id: "2", name: "剧集"), Category(id: "3", name: "综艺"), Category(id: "4", name: "动漫")]
    static func text(_ object: [String: Any], _ key: String) -> String { JianpianProvider.text(object, key) }
    static func numericID(_ value: String) -> Bool { value.range(of: "^[1-9][0-9]{0,15}$", options: .regularExpression) != nil }
    func origin() throws -> URL {
        guard let address = source.ext?.string else { throw SpiderFailure.configuration("缺少 Jpys 站点地址。") }
        let url = try URLTools.httpURL(address.trimmingCharacters(in: .whitespacesAndNewlines))
        guard url.path.isEmpty || url.path == "/", url.query == nil, url.fragment == nil else { throw SpiderFailure.configuration("Jpys 配置应为站点根地址。") }
        return url
    }
    static func signature(_ parameters: [String: String], timestamp: String) -> String {
        let query = parameters.filter { !$0.value.isEmpty }.keys.sorted().map { $0 + "=" + parameters[$0]! }.joined(separator: "&")
        let text = (query.isEmpty ? "" : query + "&") + "key=" + publicProtocolKey + "&t=" + timestamp
        return SpiderCrypto.hex(SpiderCrypto.sha1(Data(SpiderCrypto.md5(text).lowercased().utf8))).lowercased()
    }
    func request(_ path: String, _ parameters: [String: String]) async throws -> [String: Any] {
        let origin = try origin(), timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let parameters = parameters.filter { !$0.value.isEmpty }
        let endpoint = origin.appendingPathComponent("api/mw-movie/anonymous/" + path)
        var request = URLRequest(url: try URLTools.apiURL(endpoint.absoluteString, parameters: parameters))
        request.allHTTPHeaderFields = ["User-Agent": BiliSpiderProvider.agent, "Referer": origin.absoluteString,
                                      "t": timestamp, "sign": Self.signature(parameters, timestamp: timestamp), "deviceId": UUID().uuidString.lowercased()]
        let (data, _) = try await client.fetch(request, limit: 4 * 1024 * 1024)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.format("Jpys 站点不再使用已适配的 JSON 接口。") }
        guard object["code"] as? Int == 200 else {
            if [401, 403, 9530, 9540, 9550, 9560].contains(object["code"] as? Int ?? 0) { throw SpiderFailure.authentication("Jpys 接口要求登录或验证。") }
            throw SpiderFailure.upstream("Jpys 未返回有效数据。")
        }
        guard let result = object["data"] as? [String: Any] else { throw SpiderFailure.format("Jpys 响应缺少数据对象。") }
        return result
    }
    static func video(_ object: [String: Any]) -> Video? {
        let id = text(object, "vodId"), name = text(object, "vodName")
        guard numericID(id), !name.isEmpty else { return nil }
        return Video(id: id, title: VODParser.cleanText(name), poster: text(object, "vodPic"), remarks: text(object, "vodRemarks"),
                     year: text(object, "vodYear"), area: text(object, "vodArea"), genre: text(object, "vodClass"),
                     director: text(object, "vodDirector"), actors: text(object, "vodActor"),
                     summary: VODParser.cleanText(text(object, "vodContent").isEmpty ? text(object, "vodBlurb") : text(object, "vodContent")))
    }
    static func parseList(_ object: [String: Any], page: Int, search: Bool) throws -> VideoPage {
        let data = search ? object["result"] as? [String: Any] : object
        guard let data, let rows = data["list"] as? [[String: Any]] else { throw SpiderFailure.format("Jpys 列表结构已变化。") }
        return VideoPage(videos: rows.compactMap(video), categories: categories, page: page, pageCount: max(page, min(data["totalPage"] as? Int ?? page, 1000)))
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let page = max(1, min(page, 1000)), query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let category, !Self.categories.contains(where: { $0.id == category }) { throw SpiderFailure.configuration("Jpys 分类无效。") }
        let parameters = query.isEmpty ? ["type1": category ?? "1", "pageNum": String(page), "pageSize": "20"] : ["keyword": query, "pageNum": String(page), "pageSize": "20"]
        return try Self.parseList(await request(query.isEmpty ? "video/list" : "video/searchByWord", parameters), page: page, search: !query.isEmpty)
    }
    static func detail(_ object: [String: Any], id: String) throws -> Video {
        guard var video = video(object), video.id == id, let rows = object["episodeList"] as? [[String: Any]] else { throw SpiderFailure.format("Jpys 详情与请求不符。") }
        var seen = Set<String>()
        let episodes = rows.sorted { (a, b) in (a["sort"] as? Int ?? 0) < (b["sort"] as? Int ?? 0) }.compactMap { item -> Episode? in
            let nid = text(item, "nid")
            guard numericID(nid), seen.insert(nid).inserted else { return nil }
            return Episode(name: text(item, "name"), address: id + ":" + nid,
                           resolution: EpisodeResolution(parser: NativeSpider.jpys.rawValue, parseType: "native-jpys", token: "", headers: [:]))
        }
        guard !episodes.isEmpty else { throw SpiderFailure.upstream("此影片暂未发布剧集。") }
        // Qualities must be checked at play time: do not advertise login-only 720/1080p as available.
        video.lines = [PlayLine(name: "公开线路 · 依当前授权", episodes: episodes)]
        return video
    }
    func detail(id: String) async throws -> Video {
        guard Self.numericID(id) else { throw SpiderFailure.configuration("Jpys 影片 ID 无效。") }
        return try Self.detail(await request("video/detail", ["id": id]), id: id)
    }
    static func publicMedia(_ object: [String: Any], referer: String) throws -> ResolvedMedia {
        guard let rows = object["list"] as? [[String: Any]] else { throw SpiderFailure.format("Jpys 清晰度数据格式已变化。") }
        let publicRows = rows.filter { ($0["needLogin"] as? Bool) == false && ($0["flag"] as? Bool) == true }
            .sorted { ($0["resolution"] as? Int ?? 0) > ($1["resolution"] as? Int ?? 0) }
        for row in publicRows {
            if let address = row["url"] as? String, PublicWebSpiderProvider.isMedia(address) {
                return ResolvedMedia(url: try URLTools.httpURL(address), headers: ["User-Agent": BiliSpiderProvider.agent, "Referer": referer])
            }
        }
        throw SpiderFailure.authentication("此剧集没有当前访客有权播放的清晰度；不使用登录 / 会员限定线路。")
    }
    func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        let ids = episode.address.components(separatedBy: ":")
        guard episode.resolution?.parseType == "native-jpys", episode.resolution?.parser == NativeSpider.jpys.rawValue,
              ids.count == 2, ids.allSatisfy(Self.numericID) else { throw SpiderFailure.player("Jpys 剧集信息已过期，请重新打开详情。") }
        return try Self.publicMedia(await request("v2/video/episode/url", ["id": ids[0], "nid": ids[1], "clientType": "1"]), referer: origin().absoluteString)
    }
}
