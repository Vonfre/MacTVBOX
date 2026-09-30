import Foundation
import CommonCrypto

/// Native implementation of the AppGet HTTP protocol. Never loads remote executable plugins.
struct AppGetProvider {
    let client: TVClient
    let source: Source

    static func aes(_ data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw TVError.message("AppGet 密钥或 IV 长度无效。") }
        guard encrypt || (!data.isEmpty && data.count % kCCBlockSizeAES128 == 0) else { throw TVError.message("AppGet 加密响应长度无效。") }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let result = output.withUnsafeMutableBytes { dest in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count, ivBytes.baseAddress, input.baseAddress, data.count, dest.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard result == kCCSuccess else { throw TVError.message("AppGet 响应解密失败，接口密钥可能已更新。") }
        output.count = written
        return output
    }
    private func settings() async throws -> (URL, Data, Data) {
        let parts = (source.ext?.string ?? "").components(separatedBy: "|")
        guard parts.count >= 2 else { throw TVError.message("AppGet 缺少 ext 参数，请重新导入配置。") }
        var host = try URLTools.httpURL(parts[0])
        if ["txt", "json"].contains(host.pathExtension.lowercased()) {
            let (data, _) = try await client.fetch(host, limit: 8192)
            guard let text = String(data: data, encoding: .utf8) else { throw TVError.message("无法读取片源服务地址。") }
            host = try URLTools.httpURL(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let key = Data(parts[1].utf8)
        let iv = Data((parts.count > 2 ? parts[2] : parts[1]).utf8)
        guard [16, 24, 32].contains(key.count), iv.count == 16 else { throw TVError.message("AppGet 配置密钥格式无效。") }
        return (host, key, iv)
    }
    static func form(_ fields: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    private func call(_ action: String, fields: [String: String]? = nil, settings: (URL, Data, Data)) async throws -> [String: Any] {
        let (host, key, iv) = settings
        let url = host.appendingPathComponent("api.php/getappapi.index/" + action)
        var request = URLRequest(url: url)
        request.setValue("okhttp/3.10.0", forHTTPHeaderField: "User-Agent")
        if let fields {
            request.httpMethod = "POST"; request.httpBody = Self.form(fields)
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, _) = try await client.fetch(request)
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TVError.message("AppGet 返回了非预期响应。") }
        guard let encrypted = envelope["data"] as? String, let bytes = Data(base64Encoded: encrypted) else {
            let message = ConfigurationParser.scalar(envelope["msg"])
            throw TVError.message(message.isEmpty ? "片源没有返回数据，可能需要登录或已失效。" : String(message.prefix(240)))
        }
        let decoded = try Self.aes(bytes, key: key, iv: iv, encrypt: false)
        guard let result = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else { throw TVError.message("AppGet 数据结构不正确。") }
        return result
    }
    private func videos(_ items: Any?, base: URL) throws -> [Video] {
        let list = items as? [[String: Any]] ?? []
        return try VODParser.parse(JSONSerialization.data(withJSONObject: ["list": list]), baseURL: base).videos
    }
    static func requiresVerification(_ config: [String: Any]) -> Bool {
        let value = config["system_search_verify_status"]
        return (value as? Bool == true) || ["1", "true"].contains(ConfigurationParser.scalar(value).lowercased())
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let settings = try await settings()
        let query = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let home = try await call("initV119", settings: settings)
            if Self.requiresVerification(home["config"] as? [String: Any] ?? [:]) {
                throw TVError.message("该片源搜索要求验证码，当前不会自动绕过验证。请更换片源或在官方客户端完成验证。")
            }
            let result = try await call("searchList", fields: ["keywords": query, "type_id": "0", "page": String(page)], settings: settings)
            let items = try videos(result["search_list"], base: settings.0)
            return VideoPage(videos: items, page: page, pageCount: items.isEmpty ? page : page + 1)
        }
        if let category {
            let result = try await call("typeFilterVodList", fields: ["type_id": category, "page": String(page), "area": "全部", "year": "全部", "sort": "最新", "lang": "全部", "class": "全部"], settings: settings)
            let items = try videos(result["recommend_list"], base: settings.0)
            return VideoPage(videos: items, page: page, pageCount: items.isEmpty ? page : page + 1)
        }
        let home = try await call("initV119", settings: settings)
        let types = home["type_list"] as? [[String: Any]] ?? []
        var sections: [RecommendationSection] = [], categories: [Category] = []
        let titles = ["电影": "热门电影", "电视剧": "热播剧集", "连续剧": "热播剧集", "综艺": "热播综艺", "动漫": "热门动漫", "少儿": "少儿推荐", "短剧": "热门短剧", "纪录片": "纪录片精选"]
        for type in types {
            let id = ConfigurationParser.scalar(type["type_id"]), name = ConfigurationParser.scalar(type["type_name"])
            guard id != "0", !name.isEmpty else { continue }
            categories.append(Category(id: id, name: name))
            let items = try videos(type["recommend_list"], base: settings.0)
            if !items.isEmpty { sections.append(RecommendationSection(id: id, title: titles[name] ?? name, videos: items)) }
        }
        var result = VideoPage(videos: sections.flatMap(\.videos), categories: categories)
        result.recommendations = sections
        return result
    }
    func detail(id: String) async throws -> Video {
        let settings = try await settings()
        let result = try await call("vodDetail", fields: ["vod_id": id], settings: settings)
        guard let vod = result["vod"] as? [String: Any], var video = try videos([vod], base: settings.0).first else { throw TVError.message("片源未返回影片详情。") }
        video.lines = (result["vod_play_list"] as? [[String: Any]] ?? []).enumerated().compactMap { index, line in
            let info = line["player_info"] as? [String: Any] ?? [:]
            let name = ConfigurationParser.scalar(info["show"])
            var headers = info["headers"] as? [String: String] ?? [:]
            if let ua = info["user_agent"] as? String, !ua.isEmpty { headers["User-Agent"] = ua }
            let episodes = (line["urls"] as? [[String: Any]] ?? []).compactMap { item -> Episode? in
                let address = ConfigurationParser.scalar(item["url"])
                guard !address.isEmpty else { return nil }
                let resolution = EpisodeResolution(parser: ConfigurationParser.scalar(info["parse"]), parseType: ConfigurationParser.scalar(info["player_parse_type"]), token: ConfigurationParser.scalar(item["token"]), headers: headers)
                return Episode(name: ConfigurationParser.scalar(item["name"]), address: address, resolution: resolution)
            }
            return episodes.isEmpty ? nil : PlayLine(name: name.isEmpty ? "线路 \(index + 1)" : name, episodes: episodes)
        }
        // Prefer ordinary direct-media lines. Quota/login lines remain selectable, not bypassed.
        video.lines = video.lines.enumerated().sorted { lhs, rhs in
            func rank(_ line: PlayLine) -> Int {
                if line.name.contains("限") || line.name.contains("VIP") { return 2 }
                if let first = line.episodes.first, Self.isDirect(first.address), first.resolution?.parser.isEmpty != false { return 0 }
                return 1
            }
            let left = rank(lhs.element), right = rank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        return video
    }
    static func isDirect(_ address: String) -> Bool {
        guard let url = try? URLTools.httpURL(address) else { return false }
        return ["m3u8", "mp4", "m4v", "mov", "mp3", "m4a", "aac", "ts"].contains(url.pathExtension.lowercased())
    }
    func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        let headers = episode.resolution?.headers ?? [:]
        if Self.isDirect(episode.address) { return ResolvedMedia(url: try URLTools.httpURL(episode.address), headers: headers) }
        guard let resolution = episode.resolution else { throw TVError.message("播放信息不完整，请重新打开影片详情。") }
        let result: [String: Any]
        if resolution.parser.contains("url=") {
            // Preserve the source-provided query, encoding only the nested video address.
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let url = try URLTools.httpURL(resolution.parser + (episode.address.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""))
            let (data, _) = try await client.fetch(url, limit: 1024 * 1024)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TVError.message("解析服务没有返回 JSON 媒体地址。") }
            result = object
        } else {
            let settings = try await settings()
            let encrypted = try Self.aes(Data(episode.address.utf8), key: settings.1, iv: settings.2, encrypt: true).base64EncodedString()
            let response = try await call("vodParse", fields: ["parse_api": resolution.parser, "url": encrypted, "player_parse_type": resolution.parseType, "token": resolution.token], settings: settings)
            if let json = response["json"] as? String, let data = json.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] { result = object }
            else if let object = response["json"] as? [String: Any] { result = object }
            else { result = response }
        }
        guard let address = result["url"] as? String, !address.isEmpty else { throw TVError.message("解析服务未提供媒体地址。请尝试另一条线路。") }
        var finalHeaders = headers
        for (key, value) in result["header"] as? [String: String] ?? [:] { finalHeaders[key] = value }
        return ResolvedMedia(url: try URLTools.httpURL(address), headers: finalHeaders)
    }
}
