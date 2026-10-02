import Foundation

/// Public charts/search, music and MV metadata. Never substitutes another site for paid tracks.
struct KugouSpiderProvider {
    let client: TVClient
    static let agent = BiliSpiderProvider.agent
    func request(_ address: String, _ params: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: try URLTools.apiURL(address, parameters: params))
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await client.fetch(request, limit: 4 * 1024 * 1024)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.format("酷狗返回非 JSON 数据。") }
        if let status = object["status"] as? Int, status != 1 { throw SpiderFailure.upstream("酷狗接口暂不可用或需要授权。") }
        return object
    }
    static func value(_ object: [String: Any], _ key: String) -> String { JianpianProvider.text(object, key) }
    static func hash(_ string: String) -> Bool { string.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil }
    static func song(_ item: [String: Any]) -> Video? {
        let hash = value(item, "hash")
        guard Self.hash(hash) else { return nil }
        let mv = value(item, "mvhash"), title = value(item, "filename")
        let name = title.isEmpty ? value(item, "songname") : title
        guard !name.isEmpty else { return nil }
        var lines = [PlayLine(name: "音乐 · 依官方授权", episodes: [Episode(name: name, address: "song:" + hash)])]
        if Self.hash(mv) { lines.append(PlayLine(name: "MV", episodes: [Episode(name: name, address: "mv:" + mv)])) }
        return Video(id: "song:" + hash + (Self.hash(mv) ? ":" + mv : ""), title: name,
                     poster: value(item, "album_sizable_cover").replacingOccurrences(of: "{size}", with: "400"), remarks: "音乐 / MV · 非影视正片", genre: "音乐", lines: lines)
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let page = max(1, min(page, 1000)), query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let categories = [Category(id: "charts", name: "音乐榜单")]
        if !query.isEmpty {
            let object = try await request("http://mobilecdn.kugou.com/api/v3/search/song", ["format": "json", "keyword": query, "page": String(page), "pagesize": "20"])
            guard let data = object["data"] as? [String: Any], let rows = data["info"] as? [[String: Any]] else { throw SpiderFailure.format("酷狗搜索格式已变化。") }
            let total = data["total"] as? Int ?? 0
            return VideoPage(videos: rows.compactMap(Self.song), categories: categories, page: page, pageCount: max(page, (total + 19) / 20))
        }
        if page > 1 { return VideoPage(videos: [], categories: categories, page: page, pageCount: page) }
        let object = try await request("http://mobilecdnbj.kugou.com/api/v3/rank/list", ["version": "9108", "plat": "0"])
        guard let data = object["data"] as? [String: Any], let rows = data["info"] as? [[String: Any]] else { throw SpiderFailure.format("酷狗榜单格式已变化。") }
        let videos = rows.compactMap { item -> Video? in
            let id = Self.value(item, "rankid"), title = Self.value(item, "rankname")
            guard !id.isEmpty, !title.isEmpty else { return nil }
            return Video(id: "rank:" + id, title: title, poster: Self.value(item, "imgurl").replacingOccurrences(of: "{size}", with: "400"), remarks: "音乐榜单", genre: "音乐")
        }
        return VideoPage(videos: videos, categories: categories)
    }
    func detail(id: String) async throws -> Video {
        let parts = id.components(separatedBy: ":")
        if (parts.count == 2 || parts.count == 3), parts[0] == "song", Self.hash(parts[1]), parts.count != 3 || Self.hash(parts[2]) {
            // Resolve title from the official metadata response rather than persisting entire query results in IDs.
            let info = try await request("https://m.kugou.com/app/i/getSongInfo.php", ["cmd": "playInfo", "hash": parts[1]])
            let title = Self.value(info, "songName").isEmpty ? "音乐" : Self.value(info, "songName")
            let item: [String: Any] = ["hash": parts[1], "mvhash": parts.count == 3 ? parts[2] : "", "filename": title, "album_sizable_cover": Self.value(info, "imgUrl")]
            var video = Self.song(item)!
            video.lines.sort { $0.name == "MV" && $1.name != "MV" }
            return video
        }
        guard parts.count == 2, parts[0] == "rank", parts[1].range(of: "^[0-9]{1,12}$", options: .regularExpression) != nil else { throw SpiderFailure.configuration("酷狗条目 ID 无效。") }
        let object = try await request("http://mobilecdnbj.kugou.com/api/v3/rank/song", ["version": "9108", "ranktype": "0", "plat": "0", "pagesize": "200", "area_code": "1", "page": "1", "volid": "35050", "rankid": parts[1], "with_res_tag": "0"])
        guard let data = object["data"] as? [String: Any], let rows = data["info"] as? [[String: Any]] else { throw SpiderFailure.format("酷狗榜单曲目格式已变化。") }
        let songs = rows.compactMap(Self.song)
        let audio = songs.flatMap { $0.lines[0].episodes }, videos = songs.flatMap { $0.lines.count > 1 ? $0.lines[1].episodes : [] }
        var lines: [PlayLine] = []
        // Prefer MVs in the video player; official music authorization failures remain explicit.
        if !videos.isEmpty { lines.append(PlayLine(name: "MV", episodes: videos)) }
        if !audio.isEmpty { lines.append(PlayLine(name: "音乐 · 依官方授权", episodes: audio)) }
        guard !lines.isEmpty else { throw SpiderFailure.upstream("榜单暂无曲目。") }
        return Video(id: id, title: "酷狗音乐榜", genre: "音乐", lines: lines)
    }
    func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        let parts = episode.address.components(separatedBy: ":")
        guard parts.count == 2, ["song", "mv"].contains(parts[0]), Self.hash(parts[1]) else { throw SpiderFailure.player("音乐条目无效，请重新打开详情。") }
        if parts[0] == "mv" {
            let object = try await request("https://m.kugou.com/app/i/mv.php", ["cmd": "100", "hash": parts[1], "ismp3": "1", "ext": "mp4"])
            guard let qualities = object["mvdata"] as? [String: [String: Any]] else { throw SpiderFailure.authentication("此 MV 没有公开播放权限。") }
            for quality in ["sq", "rq", "le"] {
                if let url = qualities[quality]?["downurl"] as? String, let media = try? URLTools.httpURL(url) {
                    return ResolvedMedia(url: media, headers: ["User-Agent": Self.agent, "Referer": "https://m.kugou.com/"])
                }
            }
            throw SpiderFailure.authentication("此 MV 暂无可用播放地址。")
        }
        let object = try await request("https://m.kugou.com/app/i/getSongInfo.php", ["cmd": "playInfo", "hash": parts[1]])
        let error = Self.value(object, "error")
        guard error.isEmpty, let address = object["url"] as? String, let url = try? URLTools.httpURL(address) else {
            throw SpiderFailure.authentication("歌曲需付费、登录或受版权 / 地区限制；不会使用其他网站绕过授权。")
        }
        return ResolvedMedia(url: url, headers: ["User-Agent": Self.agent])
    }
}
