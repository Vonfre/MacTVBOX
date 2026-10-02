import Foundation

/// Small, site-specific HTTP readers. Never evaluates downloaded JavaScript or loads DEX.
struct PublicWebSpiderProvider {
    let client: TVClient
    let source: Source
    var kind: NativeSpider { source.nativeSpider! }
    var origin: URL {
        switch kind {
        case .firstAid: return URL(string: "https://m.youlai.cn")!
        case .trailers: return URL(string: "https://www.6huo.com")!
        case .tuxiaobei: return URL(string: "https://www.tuxiaobei.com")!
        default: return URL(string: "https://www.88kanqiu.la")!
        }
    }
    static let kinds: Set<NativeSpider> = [.firstAid, .trailers, .tuxiaobei, .kanqiu]
    static func matches(_ pattern: String, _ text: String) -> [[String]] { Dm84SpiderProvider.matches(pattern, text) }
    static func attr(_ name: String, _ text: String) -> String? { Dm84SpiderProvider.attribute(name, text) }
    static func text(_ text: String) -> String { VODParser.cleanText(text).trimmingCharacters(in: .whitespacesAndNewlines) }
    func absolute(_ value: String) -> String { URLTools.resolved(value, relativeTo: origin) }
    var headers: [String: String] { ["User-Agent": BiliSpiderProvider.agent, "Referer": origin.absoluteString + "/"] }
    func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url); request.allHTTPHeaderFields = headers
        let (data, _) = try await client.fetch(request, limit: 4 * 1024 * 1024)
        guard let html = String(data: data, encoding: .utf8) else { throw SpiderFailure.format("网页不是 UTF-8。") }
        if ["safeline-challenge", "cf-chl-", "<title>安全验证", "<title>just a moment"].contains(where: html.lowercased().contains) {
            throw SpiderFailure.authentication("网页要求浏览器验证，无法直接获取公开内容。")
        }
        return html
    }
    var categories: [Category] {
        switch kind {
        case .firstAid: return ["急救技能", "家庭生活", "急危重症", "常见损伤", "动物致伤", "海洋急救", "中毒急救", "意外事故"].enumerated().map { Category(id: "jijiu|\($0.offset)", name: $0.element) }
        case .trailers: return [Category(id: "movlist/", name: "电影预告片")]
        case .tuxiaobei: return [Category(id: "erge", name: "儿歌"), Category(id: "gushi", name: "故事"), Category(id: "guoxue", name: "国学")]
        default: return [Category(id: "all", name: "全部直播"), Category(id: "4", name: "篮球"), Category(id: "23", name: "足球"), Category(id: "21", name: "其他赛事")]
        }
    }
    func browse(category: String?, page: Int, query: String?) async throws -> VideoPage {
        let page = max(1, min(page, 1000)), query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if kind != .trailers && page > 1 { return VideoPage(videos: [], categories: categories, page: page, pageCount: page) }
        var url = origin
        switch kind {
        case .firstAid: url = origin.appendingPathComponent("jijiu")
        case .trailers:
            url = query.isEmpty ? origin.appendingPathComponent(category == nil && page == 1 ? "" : "movlist/____\(page)") : try URLTools.apiURL(origin.absoluteString, parameters: ["keyword": query, "page": String(page)])
        case .tuxiaobei:
            guard category == nil || categories.contains(where: { $0.id == category }) else { throw SpiderFailure.configuration("兔小贝分类无效。") }
            // The public site has no stable global-search endpoint. Search the three public catalogs,
            // not an unrelated web search or a made-up API. Label the scope in the adapter note.
            if !query.isEmpty {
                var videos: [Video] = [], seen = Set<String>()
                for item in categories {
                    for video in try parseList(await fetch(origin.appendingPathComponent(item.id)), category: nil, page: 1).videos where video.title.localizedCaseInsensitiveContains(query) && seen.insert(video.id).inserted { videos.append(video) }
                }
                return VideoPage(videos: videos, categories: categories)
            }
            url = origin.appendingPathComponent(category ?? "erge")
        default:
            if let category, category != "all" {
                guard categories.contains(where: { $0.id == category }) else { throw SpiderFailure.configuration("赛事分类无效。") }
                url = origin.appendingPathComponent("match/\(category)/live")
            }
        }
        var result = try parseList(await fetch(url), category: query.isEmpty ? category : nil, page: page)
        if !query.isEmpty && kind != .trailers { result.videos = result.videos.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        return result
    }
    func parseList(_ html: String, category: String?, page: Int) throws -> VideoPage {
        var videos: [Video] = [], seen = Set<String>()
        var document = html
        if kind == .firstAid, let category {
            guard let selected = categories.firstIndex(where: { $0.id == category }) else { throw SpiderFailure.configuration("急救分类无效。") }
            let sections = Self.matches("<div\\b[^>]*class=[\"']jj-title-li[\"'][^>]*>(.*?)(?=<div[^>]*>\\s*<img[^>]*class=[\"']block100|<script|</body>)", html)
            // Each section ends at its next banner; never silently substitute a different category.
            guard selected < sections.count else { throw SpiderFailure.format("急救栏目结构已变化。") }
            document = sections[selected][1]
        }
        if kind == .kanqiu {
            for block in Self.matches("<li\\b[^>]*class=[\"'][^\"']*group-game-item[^\"']*[\"'][^>]*>(.*?)</li>", html) {
                guard let id = Self.matches("/live/([0-9]+)/play", block[1]).first?[1], seen.insert(id).inserted else { continue }
                let names = Self.matches("<span\\b[^>]*class=[\"']team-name[\"'][^>]*>(.*?)</span>", block[1]).map { Self.text($0[1]) }
                guard !names.isEmpty else { continue }
                let picture = Self.matches("<img\\b([^>]*)>", block[1]).first.flatMap { Self.attr("src", $0[1]) } ?? ""
                let remarks = Self.matches("<span\\b[^>]*class=[\"']game-type[\"'][^>]*>(.*?)</span>", block[1]).first.map { Self.text($0[1]) } ?? "直播"
                videos.append(Video(id: id, title: names.joined(separator: " vs "), poster: absolute(picture), remarks: remarks, genre: "体育直播"))
            }
        } else {
            for anchor in Self.matches("<a\\b([^>]*)>(.*?)</a>", document) {
                guard let href = Self.attr("href", anchor[1]) else { continue }
                let pattern = kind == .firstAid ? "^/jijiu/article/[A-Za-z0-9]+\\.html$" : kind == .trailers ? "^/movie/[0-9]+$" : "^/play/[0-9]+$"
                guard href.range(of: pattern, options: .regularExpression) != nil, seen.insert(href).inserted else { continue }
                let image = Self.matches("<img\\b([^>]*)>", anchor[2]).first?[1] ?? ""
                let name = Self.attr("title", anchor[1]) ?? Self.attr("alt", image) ?? Self.matches("<(?:p|span)\\b[^>]*class=[\"'][^\"']*(?:tit|item-title)[^\"']*[\"'][^>]*>(.*?)</(?:p|span)>", anchor[2]).first.map { Self.text($0[1]) } ?? Self.text(anchor[2])
                guard !name.isEmpty else { continue }
                let imageURL = Self.attr("data-src", image) ?? Self.attr("src", image) ?? ""
                videos.append(Video(id: href, title: name, poster: imageURL.isEmpty ? "" : absolute(imageURL), remarks: kind == .trailers ? "预告片 · 非正片" : "", genre: kind == .firstAid ? "健康科普" : kind == .tuxiaobei ? "少儿" : "预告片"))
            }
        }
        if videos.isEmpty && !html.contains("暂无") && kind != .trailers { throw SpiderFailure.format("公开目录未返回可识别条目。") }
        let next = kind == .trailers && html.range(of: "下一页|next-page", options: .regularExpression) != nil
        return VideoPage(videos: videos, categories: categories, page: page, pageCount: next ? page + 1 : page)
    }
    func detail(id: String) async throws -> Video {
        if kind == .kanqiu {
            guard id.range(of: "^[0-9]{1,12}$", options: .regularExpression) != nil else { throw SpiderFailure.configuration("赛事 ID 无效。") }
            let text = try await fetch(origin.appendingPathComponent("live/\(id)/source"))
            return try parseSportsDetail(Data(text.utf8), id: id)
        }
        let pattern = kind == .firstAid ? "^/jijiu/article/[A-Za-z0-9]+\\.html$" : kind == .trailers ? "^/movie/[0-9]+$" : "^/play/[0-9]+$"
        guard id.range(of: pattern, options: .regularExpression) != nil else { throw SpiderFailure.configuration("网页影片 ID 无效。") }
        return try parseDetail(await fetch(URL(string: absolute(id))!), id: id)
    }
    func parseDetail(_ html: String, id: String) throws -> Video {
        let heading = Self.matches("<h[12]\\b[^>]*>(.*?)</h[12]>", html).first.map { Self.text($0[1]) }
        let title = heading ?? Self.matches("<title>(.*?)</title>", html).first.map { Self.text($0[1]).components(separatedBy: "_")[0] } ?? "视频"
        var episodes: [Episode] = []
        if kind == .trailers {
            var seen = Set<String>()
            for anchor in Self.matches("<a\\b([^>]*)>(.*?)</a>", html) {
                guard let href = Self.attr("href", anchor[1]), href.range(of: "^/show/[0-9]+$", options: .regularExpression) != nil,
                      (Self.attr("class", anchor[1]) ?? "").contains("tlist-bbs-tdtitle"), seen.insert(href).inserted else { continue }
                episodes.append(episode(Self.text(anchor[2]), absolute(href)))
            }
        } else {
            if let media = Self.mediaAddress(html) { episodes = [episode(title, absolute(media))] }
        }
        guard !episodes.isEmpty else { throw SpiderFailure.player(kind == .trailers ? "此条目暂无可播放预告片；预告片源不提供正片。" : "网页没有公开的视频直链。") }
        let picture = Self.matches("<video\\b([^>]*)>", html).first.flatMap { Self.attr("poster", $0[1]) } ?? Self.matches("<meta\\b([^>]*)>", html).first(where: { Self.attr("property", $0[1]) == "og:image" }).flatMap { Self.attr("content", $0[1]) } ?? ""
        return Video(id: id, title: title, poster: picture.isEmpty ? "" : absolute(picture), remarks: kind == .trailers ? "预告片 · 非正片" : "", lines: [PlayLine(name: kind == .trailers ? "公开预告片" : "公开视频", episodes: episodes)])
    }
    static func mediaAddress(_ html: String) -> String? {
        for tag in matches("<(?:source|video)\\b([^>]*)>", html) {
            if let src = attr("src", tag[1]), isMedia(src) { return src }
        }
        // JSON-LD contentUrl and the site's literal player setting; not a JavaScript interpreter.
        for pattern in ["[\"']contentUrl[\"']\\s*:\\s*[\"']([^\"']+)[\"']", "\\bvideo\\s*:\\s*[\"']([^\"']+)[\"']"] {
            for row in matches(pattern, html) {
                let address = row[1].replacingOccurrences(of: "\\/", with: "/")
                if isMedia(address) { return address }
            }
        }
        return nil
    }
    static func isMedia(_ value: String) -> Bool {
        guard let url = try? URLTools.httpURL(value) else { return false }
        return ["mp4", "m3u8", "mov", "m4v", "mp3", "m4a"].contains(url.pathExtension.lowercased())
    }
    func episode(_ name: String, _ address: String) -> Episode {
        Episode(name: name, address: address, resolution: EpisodeResolution(parser: kind.rawValue, parseType: "native-public-web", token: "", headers: [:]))
    }
    func parseSportsDetail(_ data: Data, id: String) throws -> Video {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let encoded = object["data"] as? String,
              encoded.count > 8, let bytes = Data(base64Encoded: String(encoded.dropFirst(6).dropLast(2))),
              let decoded = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let links = decoded["links"] as? [[String: Any]] else { throw SpiderFailure.format("赛事线路数据格式已变化。") }
        guard (decoded["shareStatusCheck"] as? Int) == 0 else { throw SpiderFailure.authentication("赛事线路需要访问授权。") }
        let lines: [PlayLine] = links.compactMap { link in
            guard (link["shareLock"] as? Int) == 0, let raw = link["url"] as? String, let media = Self.sportsMedia(raw) else { return nil }
            let name = link["name"] as? String ?? "直播"
            return PlayLine(name: name, episodes: [episode(name, media.absoluteString)])
        }
        guard !lines.isEmpty else { throw SpiderFailure.player("比赛尚未开始，或没有公开的 HTTP 直播线路。") }
        return Video(id: id, title: "体育直播", remarks: "直播 · 不支持跳转进度", genre: "体育直播", lines: lines)
    }
    static func sportsMedia(_ address: String) -> URL? {
        if isMedia(address) { return try? URLTools.httpURL(address) }
        guard let wrapper = try? URLTools.httpURL(address), wrapper.host == "play.88player.top", wrapper.path == "/m3u8.html",
              let target = URLComponents(url: wrapper, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value, isMedia(target) else { return nil }
        return try? URLTools.httpURL(target)
    }
    func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        guard episode.resolution?.parseType == "native-public-web", episode.resolution?.parser == kind.rawValue else { throw SpiderFailure.player("请重新打开原生来源详情。") }
        var url = try URLTools.httpURL(episode.address)
        if !Self.isMedia(url.absoluteString) {
            guard kind == .trailers, url.host == origin.host, url.scheme == "https", (url.port == nil || url.port == 443), url.path.range(of: "^/show/[0-9]+$", options: .regularExpression) != nil,
                  let media = Self.mediaAddress(try await fetch(url)) else { throw SpiderFailure.player("此线路不是公开的媒体直链。") }
            url = try URLTools.httpURL(media)
        }
        return ResolvedMedia(url: url, headers: headers)
    }
}
