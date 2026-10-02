import Foundation

/// Independent HTTP protocol ports for AppRJ / AppQi. No Android or executable plugin dependency.
struct LegacyAppSpiderProvider {
    let client: TVClient
    let source: Source
    var isQi: Bool { source.nativeSpider == .appQi }
    static let rjSalt = "7gp0bnd2sr85ydii2j32pcypscoc4w6c7g5spl"
    static func text(_ object: [String: Any], _ key: String) -> String { JianpianProvider.text(object, key) }
    func options() async throws -> (URL, Data, String) {
        guard let ext = source.ext?.string else { throw SpiderFailure.configuration("缺少 AppRJ / AppQi 接口配置。") }
        let parts = ext.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        var origin = try URLTools.httpURL(parts[0])
        let key = isQi && parts.count > 1 ? Data(parts[1].utf8) : Data()
        if isQi {
            guard key.count == 16 else { throw SpiderFailure.configuration("AppQi 需要 16 字节协议密钥。") }
            if origin.path != "" && origin.path != "/" {
                let (data, _) = try await client.fetch(origin, limit: 8192)
                guard let line = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).first else { throw SpiderFailure.configuration("AppQi 域名配置不可读取。") }
                origin = try URLTools.httpURL(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return (origin, key, isQi ? (parts.count > 2 ? parts[2] : "okhttp/3.14.9") : "okhttp-okgo/jeasonlzy")
    }
    static func multipart(_ parameters: [String: String], boundary: String) -> Data {
        Data((parameters.keys.sorted().map { key in
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(parameters[key]!)\r\n"
        }.joined() + "--\(boundary)--\r\n").utf8)
    }
    func request(_ path: String, _ parameters: [String: String], form: Bool = false) async throws -> [String: Any] {
        let (origin, key, agent) = try await options()
        guard let url = URL(string: origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw SpiderFailure.configuration("接口路径无效。") }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        if isQi {
            if form {
                var parts = URLComponents(); parts.queryItems = parameters.keys.sorted().map { URLQueryItem(name: $0, value: parameters[$0]) }
                request.httpBody = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            } else {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys])
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        } else {
            var signed = parameters
            let timestamp = String(Int(Date().timeIntervalSince1970))
            signed["timestamp"] = timestamp; signed["sign"] = SpiderCrypto.md5(Self.rjSalt + timestamp).lowercased()
            let boundary = "MacTVBOX-" + UUID().uuidString
            request.httpBody = Self.multipart(signed, boundary: boundary)
            request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        }
        let (bytes, _) = try await client.fetch(request)
        return try Self.decode(bytes, key: isQi ? key : nil)
    }
    static func decode(_ data: Data, key: Data?) throws -> [String: Any] {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.format("App 接口未返回 JSON。") }
        if let code = envelope["code"] as? Int, [401, 403].contains(code) { throw SpiderFailure.authentication("App 接口要求登录或验证。") }
        if let key {
            guard let encrypted = envelope["data"] as? String, let bytes = Data(base64Encoded: encrypted) else { throw SpiderFailure.format("AppQi 响应缺少加密数据。") }
            let plain = try AppGetProvider.aes(bytes, key: key, iv: key, encrypt: false)
            guard let object = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else { throw SpiderFailure.format("AppQi 解密结果不是 JSON。") }
            return object
        }
        guard envelope["code"] as? Int == 1, let object = envelope["data"] as? [String: Any] else { throw SpiderFailure.upstream("AppRJ 未返回有效数据。") }
        return object
    }
    static func videos(_ items: [[String: Any]]) throws -> [Video] {
        let data = try JSONSerialization.data(withJSONObject: ["list": items])
        return try VODParser.parse(data).videos
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let page = max(1, min(page, 1000)), query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let object: [String: Any], listKey: String
        var categories: [Category] = []
        if isQi {
            if !query.isEmpty {
                object = try await request("/api.php/qijiappapi.index/searchList", ["type_id": "0", "keywords": query, "page": String(page)]); listKey = "search_list"
            } else if let category {
                object = try await request("/api.php/qijiappapi.index/typeFilterVodList?page=\(page)", ["type_id": category]); listKey = "recommend_list"
            } else {
                let home = try await request("/api.php/qijiappapi.index/initV120", [:]); listKey = "recommend_list"
                categories = Self.categories(home["type_list"])
                if (home[listKey] as? [[String: Any]])?.isEmpty == true, let first = categories.first {
                    // A blank promotional homepage is not a blank library. Use a real returned category.
                    object = try await request("/api.php/qijiappapi.index/typeFilterVodList?page=1", ["type_id": first.id])
                } else { object = home }
            }
        } else {
            if !query.isEmpty {
                object = try await request("/v3/home/search", ["keyword": query, "limit": "12", "page": String(page)]); listKey = "list"
            } else if let category {
                object = try await request("/v3/home/type_search", ["type_id": category, "limit": "12", "page": String(page)]); listKey = "list"
            } else {
                let home = try await request("/v3/type/top_type", [:]); categories = Self.categories(home["list"])
                guard let first = categories.first else { throw SpiderFailure.format("AppRJ 未返回分类。") }
                object = try await request("/v3/home/type_search", ["type_id": first.id, "limit": "12", "page": "1"]); listKey = "list"
            }
        }
        guard let rows = object[listKey] as? [[String: Any]] else { throw SpiderFailure.format("App 列表结构已变化。") }
        let hasNext = (category != nil || !query.isEmpty) && rows.count >= (isQi ? 30 : 12)
        return VideoPage(videos: try Self.videos(rows), categories: categories, page: page, pageCount: hasNext ? page + 1 : page)
    }
    static func categories(_ value: Any?) -> [Category] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            let id = text(item, "type_id"), name = text(item, "type_name")
            return id.isEmpty || name.isEmpty ? nil : Category(id: id, name: name)
        }
    }
    func detail(id: String) async throws -> Video {
        guard id.range(of: "^[0-9]{1,16}$", options: .regularExpression) != nil else { throw SpiderFailure.configuration("App 影片 ID 无效。") }
        let object = try await request(isQi ? "/api.php/qijiappapi.index/vodDetail" : "/v3/home/vod_details", ["vod_id": id])
        return try Self.detail(object, id: id, qi: isQi)
    }
    static func detail(_ object: [String: Any], id: String, qi: Bool) throws -> Video {
        guard let vod = qi ? object["vod"] as? [String: Any] : object else { throw SpiderFailure.format("App 详情缺少影片字段。") }
        guard text(vod, "vod_id") == id, var video = try videos([vod]).first else { throw SpiderFailure.format("App 返回了不同影片的详情。") }
        let groups = object["vod_play_list"] as? [[String: Any]] ?? []
        video.lines = try groups.enumerated().compactMap { index, group in
            let info = qi ? (group["player_info"] as? [String: Any] ?? [:]) : group
            let name = text(info, qi ? "show" : "name")
            let episodes = try (group["urls"] as? [[String: Any]] ?? []).compactMap { row -> Episode? in
                let address = text(row, "url"), parserURL = text(row, "parse_api_url")
                guard !address.isEmpty || !parserURL.isEmpty else { return nil }
                let context: [String: Any] = qi ? ["parse": text(info, "parse"), "endpoint": parserURL, "token": text(row, "token")] : ["parsers": group["parse_urls"] as? [String] ?? []]
                let parser = String(data: try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]), encoding: .utf8)!
                var headers: [String: String] = [:]
                for (field, header) in [("ua", "User-Agent"), ("referer", "Referer")] { let value = text(info, field); if !value.isEmpty { headers[header] = value } }
                return Episode(name: text(row, "name"), address: address,
                               resolution: EpisodeResolution(parser: parser, parseType: qi ? "native-appqi" : "native-apprj", token: "", headers: headers))
            }
            return episodes.isEmpty ? nil : PlayLine(name: name.isEmpty ? "线路\(index + 1)" : name, episodes: episodes)
        }
        guard !video.lines.isEmpty else { throw SpiderFailure.upstream("接口返回了影片资料，但播放线路为空；可能已下架或需要授权。") }
        return video
    }
    func jsonURL(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.allHTTPHeaderFields = headers
        let (data, _) = try await client.fetch(request, limit: 1024 * 1024)
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.player("解析器返回网页或验证页，而非可识别的 JSON。") }
        if [401, 403].contains(result["code"] as? Int ?? 0) { throw SpiderFailure.authentication("解析器要求登录或验证。") }
        return result
    }
    static func media(_ object: [String: Any], headers: [String: String]) throws -> ResolvedMedia {
        let nested = object["data"] as? [String: Any] ?? object
        guard let address = nested["url"] as? String, PublicWebSpiderProvider.isMedia(address) else { throw SpiderFailure.player("解析器没有返回可播放的 HTTP 媒体直链。") }
        var headers = headers
        if let agent = nested["UA"] as? String, agent.rangeOfCharacter(from: .controlCharacters) == nil { headers["User-Agent"] = agent }
        return ResolvedMedia(url: try URLTools.httpURL(address), headers: headers)
    }
    func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        guard let resolution = episode.resolution, resolution.parseType == (isQi ? "native-appqi" : "native-apprj"),
              let context = try JSONSerialization.jsonObject(with: Data(resolution.parser.utf8)) as? [String: Any] else { throw SpiderFailure.player("剧集解析信息已过期，请重新打开详情。") }
        let (_, _, agent) = try await options()
        var headers = resolution.headers; if headers["User-Agent"] == nil { headers["User-Agent"] = agent }
        if PublicWebSpiderProvider.isMedia(episode.address) { return ResolvedMedia(url: try URLTools.httpURL(episode.address), headers: headers) }
        if isQi {
            if let endpoint = context["endpoint"] as? String, !endpoint.isEmpty {
                if PublicWebSpiderProvider.isMedia(endpoint) { return ResolvedMedia(url: try URLTools.httpURL(endpoint), headers: headers) }
                return try Self.media(await jsonURL(URLTools.httpURL(endpoint), headers: headers), headers: headers)
            }
            let object = try await request("/api.php/qijiappapi.index/vodParse", ["parse_api": Self.text(context, "parse"), "url": episode.address, "token": Self.text(context, "token")], form: true)
            if let json = object["json"] as? String, let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] { return try Self.media(decoded, headers: headers) }
            return try Self.media(object, headers: headers)
        }
        let parsers = context["parsers"] as? [String] ?? []
        var lastError: Error = SpiderFailure.player("没有可用解析器，且线路不是媒体直链。")
        // Try this episode's declared parsers, not unrelated sources or another title.
        for prefix in parsers.prefix(4) where !prefix.isEmpty {
            try Task.checkCancellation()
            do {
                let timestamp = String(Int(Date().timeIntervalSince1970))
                let address = prefix + episode.address + "&sign=" + SpiderCrypto.md5(Self.rjSalt + timestamp).lowercased() + "&timestamp=" + timestamp
                return try Self.media(await jsonURL(URLTools.httpURL(address), headers: headers), headers: headers)
            } catch is CancellationError { throw CancellationError() }
            catch let error as SpiderFailure { if case .authentication = error { throw error }; lastError = error }
            catch { lastError = error }
        }
        throw lastError
    }
}
