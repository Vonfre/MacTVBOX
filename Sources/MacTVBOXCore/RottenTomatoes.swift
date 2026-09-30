import Foundation

extension RankingClient {
    /// Read public, inert structured metadata only. Never evaluate webpage scripts.
    public static func parseRottenTomatoes(_ data: Data) throws -> [RankedTitle] {
        guard data.count <= 4 * 1024 * 1024 else { throw TVError.message("烂番茄页面超过安全大小限制。") }
        let html = String(decoding: data, as: UTF8.self)
        let regex = try NSRegularExpression(pattern: #"<script\b[^>]*\btype\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        var media: [[String: Any]] = []
        func collect(_ value: Any, depth: Int = 0) {
            guard depth < 12 else { return }
            if let list = value as? [Any] { for item in list { collect(item, depth: depth + 1) }; return }
            guard let node = value as? [String: Any] else { return }
            let type = node["@type"] as? String ?? ""
            if type == "Movie" || type == "TVSeries" { media.append(node); return }
            for key in ["@graph", "itemListElement", "item"] {
                if let child = node[key] { collect(child, depth: depth + 1) }
            }
        }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let object = try? JSONSerialization.jsonObject(with: Data(html[range].utf8)) else { continue }
            collect(object)
        }
        var seen = Set<String>()
        let items = media.compactMap { item -> RankedTitle? in
            guard let name = item["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rawURL = item["url"] as? String, let url = URL(string: rawURL),
                  url.scheme == "https", url.host == "www.rottentomatoes.com", url.user == nil, url.password == nil,
                  url.port == nil, url.path.hasPrefix("/m/") || url.path.hasPrefix("/tv/"),
                  seen.insert(url.path).inserted else { return nil }
            let rating = item["aggregateRating"] as? [String: Any]
            let raw = ConfigurationParser.scalar(rating?["ratingValue"])
            let value = Double(raw)
            let isTomatometer = (rating?["name"] as? String) == "Tomatometer"
            let score = isTomatometer && value != nil && (0...100).contains(value!) ? String(format: "%.0f%%", value!) : ""
            let image = item["image"] as? String ?? (item["image"] as? [String: Any])?["url"] as? String ?? ""
            let poster = (try? URLTools.httpURL(image)) != nil ? image : ""
            let year = String((item["dateCreated"] as? String ?? "").prefix(4))
            let video = Video(id: "rt:" + url.path, title: VODParser.cleanText(name), poster: poster,
                              remarks: score.isEmpty ? "暂无新鲜度" : "新鲜度 " + score,
                              year: year.allSatisfy(\.isNumber) ? year : "")
            return RankedTitle(video: video, subjectURL: url, score: score)
        }
        guard !items.isEmpty else { throw TVError.message("烂番茄公开页面暂不可读取（页面变化、验证或无榜单数据）。可打开来源网页；应用不会绕过验证。") }
        return Array(items.prefix(24))
    }
}
