import Foundation

struct GuaziAuth {
    let token: String
    let userID: String
    var referer: String
    let created: Date
}

/// Coalesces authentication across concurrent requests, scoped to one TVClient and API origin.
actor GuaziSessions {
    private var cached: [String: GuaziAuth] = [:]
    private var pending: [String: Task<GuaziAuth, Error>] = [:]
    func session(key: String, create: @escaping () async throws -> GuaziAuth) async throws -> GuaziAuth {
        if let value = cached[key], Date().timeIntervalSince(value.created) < 1100 { return value }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await create() }; pending[key] = task
        do {
            let value = try await task.value
            cached[key] = value; pending[key] = nil
            return value
        } catch { pending[key] = nil; throw error }
    }
    func invalidate(key: String, token: String) { if cached[key]?.token == token { cached[key] = nil } }
}

struct GuaziProvider {
    let client: TVClient
    let source: Source
    private var base: URL {
        get throws {
            var options: [String: JSONValue] = [:]
            if case .object(let value) = source.ext { options = value }
            else if let text = source.ext?.string, !text.isEmpty {
                guard let data = text.data(using: .utf8), let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { throw SpiderFailure.configuration("瓜子 ext 应为 JSON 配置。") }
                options = parsed
            }
            let host = options["sites"]?.string?.split(separator: ",").first.map(String.init) ?? "https://api.h27sq4f.com"
            let url = try URLTools.httpURL(host)
            guard url.query == nil, url.fragment == nil else { throw SpiderFailure.configuration("瓜子 API 地址无效。") }
            return url
        }
    }
    static let categories = [Category(id: "1", name: "电影"), Category(id: "2", name: "剧集"), Category(id: "3", name: "综艺"), Category(id: "4", name: "动漫"), Category(id: "64", name: "短剧")]
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.format("瓜子响应不是 JSON 对象。") }
        return value
    }
    static func form(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.map { $0.0.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.1.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
    }
    static func envelope(_ parameters: [String: String], token: String, time: Int = Int(Date().timeIntervalSince1970)) throws -> [(String, String)] {
        let key = SpiderCrypto.nonce(), iv = SpiderCrypto.nonce()
        let plain = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys, .withoutEscapingSlashes])
        let encrypted = try AppGetProvider.aes(plain, key: Data(key.utf8), iv: Data(iv.utf8), encrypt: true)
        let keys = try JSONSerialization.data(withJSONObject: ["key": key, "iv": iv], options: [.sortedKeys])
        let wrapped = try SpiderCrypto.rsa(keys, pem: GuaziProtocol.requestPublicKey, encrypt: true).base64EncodedString()
        var fields = [("token_id", ""), ("token", token), ("phone_type", "1"), ("request_key", SpiderCrypto.hex(encrypted)), ("app_id", "1"), ("time", String(time)), ("keys", wrapped)]
        let signature = SpiderCrypto.md5(fields.map { $0.0 + "=" + $0.1 }.joined(separator: ",") + "*&zvdvdvddbfikkkumtmdwqppp?|4Y!s!2br")
        fields += [("signature", signature), ("phone_model", "apple-macos"), ("ad_version", "1")]
        return fields
    }
    static func decoded(_ response: [String: Any]) throws -> [String: Any] {
        guard let code = response["code"] as? Int, code == 200 else {
            let code = response["code"] as? Int ?? 0
            if code == 401 || code == 403 { throw SpiderFailure.authentication("瓜子会话被拒绝，请稍后重试。") }
            throw SpiderFailure.upstream("瓜子返回状态 \(code)：" + String((response["msg"] as? String ?? "未知响应").prefix(120)))
        }
        guard let body = response["data"] as? [String: Any], let ciphertext = body["response_key"] as? String,
              let wrapped = body["keys"] as? String, wrapped.count < 16384, let bytes = Data(base64Encoded: wrapped, options: .ignoreUnknownCharacters) else { throw SpiderFailure.format("瓜子响应缺少加密数据。") }
        let keys = try object(SpiderCrypto.rsa(bytes, pem: GuaziProtocol.responsePrivateKey, encrypt: false))
        guard let key = keys["key"] as? String, let iv = keys["iv"] as? String else { throw SpiderFailure.format("瓜子响应密钥格式已变化。") }
        return try object(AppGetProvider.aes(SpiderCrypto.unhex(ciphertext), key: Data(key.utf8), iv: Data(iv.utf8), encrypt: false))
    }
    private func send(_ path: String, _ parameters: [String: String], token: String) async throws -> [String: Any] {
        try Task.checkCancellation()
        var request = URLRequest(url: try base.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpBody = try Self.form(Self.envelope(parameters, token: token))
        request.allHTTPHeaderFields = ["lang": "zh_cn", "User-Agent": "okhttp/3.12.0", "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "code": "GZ0313", "version": "2606029", "packagename": "com.v54f07a912.t4ee50f184.dbb1e7669f20260721", "ver": "3.0.4.8", "api-ver": "3.0.4.8", "Referer": try base.absoluteString]
        let (data, _) = try await client.fetch(request)
        return try Self.object(data)
    }
    private func login() async throws -> GuaziAuth {
        // Protocol guest session. Uses random app-session identifiers, never a Mac hardware ID.
        let identifier = UUID().uuidString
        var device = SpiderCrypto.bigEndian(UInt32(Date().timeIntervalSince1970))
        device += SpiderCrypto.bigEndian(UInt32.random(in: .min ... .max))
        device += Data([3, 0]); device += SpiderCrypto.bigEndian(SpiderCrypto.javaHash(identifier))
        let mac = SpiderCrypto.hmacSHA1(device, key: "d6fc3a4a06adbde89223bvefedc24fecde188aaa9161").base64EncodedString()
        device += SpiderCrypto.bigEndian(SpiderCrypto.javaHash(mac))
        var parameters = ["new_key": SpiderCrypto.hex(SpiderCrypto.sha1(Data(identifier.utf8))), "old_key": device.base64EncodedString()]
        var response = try await send("App/Authentication/Device/signIn", parameters, token: "")
        if response["code"] as? Int == 403 {
            parameters["recommend_id"] = ""
            response = try await send("App/Authentication/Device/signUp", parameters, token: "")
        }
        let auth = try Self.decoded(response)
        guard let token = auth["token"] as? String, !token.isEmpty else { throw SpiderFailure.authentication("瓜子没有返回可用会话。") }
        let profile = try Self.decoded(await send("App/UserInfo/getUserInfo", [:], token: token))
        let referer = profile["playRef"] as? String ?? "http://WJiZxLXA2.com/"
        _ = try URLTools.httpURL(referer)
        return GuaziAuth(token: token, userID: JianpianProvider.text(auth, "app_user_id"), referer: referer, created: Date())
    }
    private func auth() async throws -> GuaziAuth {
        let value = try await client.guaziSessions.session(key: base.absoluteString) { try await login() }
        try Task.checkCancellation()
        return value
    }
    private func request(_ path: String, parameters: (GuaziAuth) -> [String: String]) async throws -> [String: Any] {
        var session = try await auth()
        var response = try await send(path, parameters(session), token: session.token)
        if [401, 403].contains(response["code"] as? Int ?? 0) {
            await client.guaziSessions.invalidate(key: try base.absoluteString, token: session.token)
            session = try await auth()
            response = try await send(path, parameters(session), token: session.token)
        }
        return try Self.decoded(response)
    }
    static func list(_ json: [String: Any], page: Int, categories: [Category] = []) throws -> VideoPage {
        guard let items = json["list"] as? [[String: Any]] else { throw SpiderFailure.format("瓜子列表字段缺失。") }
        let videos = try items.map { try video($0) }
        return VideoPage(videos: videos, categories: categories, page: page, pageCount: items.isEmpty ? page : page + 1)
    }
    static func video(_ item: [String: Any]) throws -> Video {
        let id = JianpianProvider.text(item, "vod_id")
        let name = JianpianProvider.text(item, "vod_name").isEmpty ? JianpianProvider.text(item, "c_name") : JianpianProvider.text(item, "vod_name")
        guard id.range(of: "^[0-9]+$", options: .regularExpression) != nil, !name.isEmpty else { throw SpiderFailure.format("瓜子条目缺少 ID 或标题。") }
        let poster = JianpianProvider.text(item, "vod_pic").isEmpty ? JianpianProvider.text(item, "c_pic") : JianpianProvider.text(item, "vod_pic")
        return Video(id: id, title: VODParser.cleanText(name), poster: (try? URLTools.httpURL(poster))?.absoluteString ?? "", remarks: JianpianProvider.text(item, "new_continue"), year: JianpianProvider.text(item, "vod_addtime"), area: JianpianProvider.text(item, "vod_area"), director: JianpianProvider.text(item, "vod_director"), actors: JianpianProvider.text(item, "vod_actor"), summary: VODParser.cleanText(JianpianProvider.text(item, "vod_use_content")))
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let page = max(1, page), json: [String: Any]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            json = try await request("App/Index/findMoreVod") { _ in ["keywords": query.trimmingCharacters(in: .whitespacesAndNewlines), "order_val": "1", "page": String(page)] }
        } else if let category {
            guard Self.categories.contains(where: { $0.id == category }) else { throw SpiderFailure.configuration("瓜子分类无效。") }
            json = try await request("App/IndexList/indexList") { _ in ["area": "0", "year": "0", "pageSize": "30", "sort": "d_id", "sub": "0", "page": String(page), "tid": category] }
        } else { json = try await request("App/IndexList/choiceList") { _ in ["pid": "1"] } }
        var result = try Self.list(json, page: page, categories: category == nil && query == nil ? Self.categories : [])
        // Search/home APIs do not expose a paginated contract; do not repeat page one forever.
        if category == nil { result.pageCount = page }
        return result
    }
    func detail(id: String) async throws -> Video {
        guard id.range(of: "^[0-9]+$", options: .regularExpression) != nil else { throw SpiderFailure.configuration("瓜子影片 ID 无效。") }
        let info = try await request("App/IndexPlay/playInfo") { auth in ["token_id": auth.userID, "vod_id": id, "mobile_time": String(Int(Date().timeIntervalSince1970)), "token": auth.token] }
        let episodes = try await request("App/Resource/Vurl/show") { _ in ["vurl_cloud_id": "2", "vod_d_id": id] }
        guard var item = info["vodInfo"] as? [String: Any] else { throw SpiderFailure.format("瓜子详情字段缺失。") }
        if let returned = item["vod_id"], JianpianProvider.text(["id": returned], "id") != id { throw SpiderFailure.format("瓜子返回了不同影片。") }
        item["vod_id"] = id
        var result = try Self.video(item)
        result.lines = try Self.lines(episodes)
        return result
    }
    static func parameters(_ value: String) throws -> [String: String] {
        guard !value.isEmpty, value.count < 32768 else { throw SpiderFailure.player("瓜子剧集参数为空或过长。") }
        var result: [String: String] = [:]
        for part in value.split(separator: "&") {
            let fields = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { throw SpiderFailure.player("瓜子剧集参数格式无效。") }
            let key = String(fields[0]), val = String(fields[1])
            guard !key.isEmpty, !val.isEmpty, result[key] == nil else { throw SpiderFailure.player("瓜子剧集参数缺失或重复。") }
            result[key] = val
        }
        guard result["vod_d_id"] != nil || result["vod_id"] != nil else { throw SpiderFailure.player("瓜子剧集缺少影片 ID。") }
        if let id = result.removeValue(forKey: "vod_d_id") {
            guard result["vod_id"] == nil || result["vod_id"] == id else { throw SpiderFailure.player("瓜子剧集包含冲突的影片 ID。") }
            result["vod_id"] = id
        }
        return result
    }
    static func lines(_ json: [String: Any]) throws -> [PlayLine] {
        guard let entries = json["list"] as? [[String: Any]] else { throw SpiderFailure.format("瓜子缺少剧集列表。") }
        let qualities = ["3840", "2160", "1080", "720", "480", "360", "240"]
        // Keep each advertised quality rather than silently choosing one. Never invent 4K.
        let lines = qualities.compactMap { quality -> PlayLine? in
            let episodes = entries.enumerated().compactMap { index, entry -> Episode? in
                guard let play = entry["play"] as? [String: Any], let option = play[quality] as? [String: Any], let param = option["param"] as? String, (try? parameters(param)) != nil else { return nil }
                let title = JianpianProvider.text(entry, "title")
                return Episode(name: (title.isEmpty ? "第\(index + 1)集" : title) + " [\(quality)P]", address: Data(param.utf8).base64EncodedString(), resolution: EpisodeResolution(parser: quality, parseType: "native-guazi", token: "", headers: [:]))
            }
            return episodes.isEmpty ? nil : PlayLine(name: "瓜子 · \(quality)P", episodes: episodes)
        }
        guard !lines.isEmpty else { throw SpiderFailure.player("瓜子未提供可解析的剧集线路。") }
        return lines
    }
    func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        guard episode.address.count < 65536, let data = Data(base64Encoded: episode.address), let value = String(data: data, encoding: .utf8) else { throw SpiderFailure.player("瓜子剧集标识无效，请重新打开详情。") }
        let parameters = try Self.parameters(value)
        let json = try await request("App/Resource/VurlDetail/showOne") { _ in parameters }
        guard let raw = json["url"] as? String, !raw.isEmpty else { throw SpiderFailure.player("瓜子返回空播放地址，当前线路不可用。") }
        let url = try URLTools.httpURL(raw)
        guard ["m3u8", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) else { throw SpiderFailure.player("瓜子返回的不是受支持的视频直链。") }
        return ResolvedMedia(url: url, headers: ["User-Agent": "Lavf/57.83.100", "Referer": try await auth().referer])
    }
}
