import Foundation

/// Site-specific HTTP adapter. HTML is parsed as data; remote scripts are never evaluated.
public struct Dm84SpiderProvider {
    let client: TVClient
    let source: Source
    private static let origin = URL(string: "https://dm84.net")!
    private static let agent = BiliSpiderProvider.agent
    public init(client: TVClient = TVClient(), source: Source) { self.client = client; self.source = source }

    private func html(_ url: URL, referer: URL = origin) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        let (data, _) = try await client.fetch(request, limit: 4 * 1024 * 1024)
        guard let text = String(data: data, encoding: .utf8) else { throw SpiderFailure.format("动漫84页面不是 UTF-8。") }
        try Self.checkChallenge(text)
        return text
    }
    static func checkChallenge(_ html: String) throws {
        let text = html.lowercased()
        if ["safeline-challenge", "cf-chl-", "<title>just a moment", "<title>人机验证", "<title>安全验证"].contains(where: text.contains) {
            throw SpiderFailure.authentication("动漫84上游要求浏览器验证，原生插件不会绕过验证。")
        }
    }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    static func attribute(_ name: String, _ tag: String) -> String? {
        matches("(?:^|\\s)" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*([\"'])(.*?)\\1", tag).first.map { decode($0[2]) }
    }
    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
    static func validID(_ value: String) -> Bool { value.range(of: "^[1-9][0-9]{0,11}$", options: .regularExpression) != nil }
    public func browse(category: String? = nil, page: Int = 1, query: String? = nil) async throws -> VideoPage {
        let page = max(1, min(page, 10000))
        let url: URL
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Site's subsequent search pages encode the keyword in the route, not a pg query.
            if page == 1 { url = try URLTools.apiURL(Self.origin.absoluteString + "/s----------.html", parameters: ["wd": query]) }
            else {
                let safe = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                url = try URLTools.httpURL(Self.origin.absoluteString + "/s-\(safe)---------\(page).html")
            }
        } else if let category {
            guard ["1", "2", "3", "4"].contains(category) else { throw SpiderFailure.configuration("动漫84分类 ID 无效。") }
            url = Self.origin.appendingPathComponent(page == 1 ? "list-\(category).html" : "list-\(category)-\(page).html")
        } else { url = Self.origin }
        return try Self.parseList(await html(url), page: page)
    }
    static func parseList(_ html: String, page: Int) throws -> VideoPage {
        try checkChallenge(html)
        var seen = Set<String>(), videos: [Video] = []
        for block in matches("<div\\b[^>]*class=[\"'][^\"']*\\bitem\\b[^\"']*[\"'][^>]*>(.*?)</div>", html) {
            let anchors = matches("<a\\b([^>]*)>(.*?)</a>", block[1])
            guard let anchor = anchors.first(where: { attribute("href", $0[1])?.range(of: "^/v/[1-9][0-9]*\\.html$", options: .regularExpression) != nil }),
                  let href = attribute("href", anchor[1]), let id = matches("/v/([0-9]+)\\.html", href).first?[1], seen.insert(id).inserted else { continue }
            let titleAnchor = anchors.first(where: { (attribute("class", $0[1]) ?? "").split(separator: " ").contains("title") }) ?? anchor
            let title = VODParser.cleanText(attribute("title", titleAnchor[1]) ?? titleAnchor[2])
            guard !title.isEmpty else { continue }
            let poster = anchors.compactMap { attribute("data-bg", $0[1]) }.first ?? ""
            let remarks = matches("<span\\b[^>]*class=[\"']desc[\"'][^>]*>(.*?)</span>", block[1]).first?[1] ?? ""
            videos.append(Video(id: id, title: title, poster: URLTools.resolved(poster, relativeTo: origin), remarks: VODParser.cleanText(remarks)))
        }
        // Distinguish a valid empty search result from an unrelated HTML/error page.
        guard !videos.isEmpty || html.contains("没有找到") || html.contains("暂无数据") else { throw SpiderFailure.format("动漫84未返回影片列表，可能是站点改版或上游验证。") }
        let pageNumbers = matches("href=[\"']/(?:list-[1-4]-|s-[^\"']*---------)([0-9]+)\\.html", html).compactMap { Int($0[1]) }
        return VideoPage(videos: videos, categories: [Category(id: "1", name: "国产动漫"), Category(id: "2", name: "日本动漫"), Category(id: "3", name: "欧美动漫"), Category(id: "4", name: "动漫电影")], page: page, pageCount: max(page, pageNumbers.max() ?? page))
    }
    public func detail(id: String) async throws -> Video {
        guard Self.validID(id) else { throw SpiderFailure.configuration("动漫84影片 ID 无效。") }
        return try Self.parseDetail(await html(Self.origin.appendingPathComponent("v/\(id).html")), id: id)
    }
    static func parseDetail(_ html: String, id: String) throws -> Video {
        try checkChallenge(html)
        guard validID(id), let heading = matches("<h1\\b[^>]*>(.*?)</h1>", html).first else { throw SpiderFailure.format("动漫84详情缺少标题。") }
        var meta: [String: String] = [:]
        for tag in matches("<meta\\b([^>]*)>", html) {
            if let key = attribute("property", tag[1]) ?? attribute("name", tag[1]), let value = attribute("content", tag[1]) { meta[key] = value }
        }
        var grouped: [Int: [(Int, Episode)]] = [:], seen = Set<String>()
        for list in matches("<ul\\b[^>]*class=[\"'][^\"']*\\bplay_list\\b[^\"']*[\"'][^>]*>(.*?)</ul>", html) {
            for anchor in matches("<a\\b([^>]*)>(.*?)</a>", list[1]) {
                guard let href = attribute("href", anchor[1]), let ids = matches("^/p/([0-9]+)-([0-9]+)-([0-9]+)\\.html$", href).first,
                      ids[1] == id, let line = Int(ids[2]), let number = Int(ids[3]), seen.insert(href).inserted else { continue }
                let episode = Episode(name: VODParser.cleanText(anchor[2]), address: origin.absoluteString + href,
                                      resolution: EpisodeResolution(parser: "dm84", parseType: "native-dm84", token: "", headers: [:]))
                grouped[line, default: []].append((number, episode))
            }
        }
        let lines = grouped.keys.sorted().map { key in PlayLine(name: "线路\(key)", episodes: grouped[key]!.sorted { $0.0 < $1.0 }.map(\.1)) }
        guard !lines.isEmpty else { throw SpiderFailure.format("动漫84详情没有匹配的剧集列表。") }
        return Video(id: id, title: VODParser.cleanText(heading[1]), poster: meta["og:image"] ?? "", year: meta["og:video:release_date"] ?? "", area: meta["og:video:area"] ?? "", genre: meta["og:video:class"] ?? "", director: meta["og:video:director"] ?? "", actors: meta["og:video:actor"] ?? "", summary: meta["og:description"] ?? "", lines: lines)
    }
    static func playerFrame(_ html: String) throws -> URL {
        try checkChallenge(html)
        // Only the observed parser protocol is supported, not arbitrary iframes or ad scripts.
        for tag in matches("<iframe\\b([^>]*)>", html) {
            if let src = attribute("src", tag[1]), let url = try? URLTools.httpURL(URLTools.resolved(src, relativeTo: origin)),
               url.scheme == "https", url.host == "hhjx.hhplayer.com", url.port == nil { return url }
        }
        throw SpiderFailure.player("动漫84使用了尚未适配的网页解析器，或需要浏览器验证。")
    }
    static func bootstrap(_ html: String) throws -> Data {
        try checkChallenge(html)
        guard let json = matches("window\\.__HHJX_BOOTSTRAP__\\s*=\\s*(\\{[^\\r\\n]*?\\})\\s*;", html).first?[1],
              let data = json.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["url"] as? String, !url.isEmpty, url.count <= 32768,
              let key = object["key"] as? String, !key.isEmpty, let time = object["t"] as? NSNumber else { throw SpiderFailure.format("动漫84解析器缺少合法的请求信息。") }
        return try JSONSerialization.data(withJSONObject: ["url": url, "key": key, "t": time, "client_fallback": false])
    }
    static func parsePlayer(_ data: Data, referer: URL) throws -> ResolvedMedia {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpiderFailure.format("动漫84解析器没有返回 JSON。") }
        guard object["code"] as? Int == 200, let address = object["url"] as? String else { throw SpiderFailure.player("动漫84解析失败：" + String((object["msg"] as? String ?? "未知响应").prefix(150))) }
        let url = try URLTools.httpURL(address)
        guard ["mp4", "m3u8", "m4v", "mov"].contains(url.pathExtension.lowercased()), (object["ext"] as? String ?? "").isEmpty else { throw SpiderFailure.player("解析器返回了二次解析地址而非受支持的媒体直链。") }
        return ResolvedMedia(url: url, headers: ["User-Agent": agent, "Referer": referer.absoluteString])
    }
    public func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        let url = try URLTools.httpURL(episode.address)
        guard episode.resolution?.parseType == "native-dm84", url.scheme == "https", url.host == Self.origin.host, url.port == nil,
              url.query == nil, url.fragment == nil, url.path.range(of: "^/p/[1-9][0-9]*-[0-9]+-[0-9]+\\.html$", options: .regularExpression) != nil else { throw SpiderFailure.player("动漫84剧集地址无效，请重新打开详情。") }
        let frame = try Self.playerFrame(await html(url))
        let body = try Self.bootstrap(await html(frame, referer: url))
        var request = URLRequest(url: URL(string: "/api/parse", relativeTo: frame)!.absoluteURL)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        request.setValue(frame.absoluteString, forHTTPHeaderField: "Referer")
        let (data, _) = try await client.fetch(request, limit: 1024 * 1024)
        // Avoid exposing ephemeral parser keys to media hosts.
        return try Self.parsePlayer(data, referer: URL(string: "https://hhjx.hhplayer.com/")!)
    }
}
