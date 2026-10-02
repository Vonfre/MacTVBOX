import Foundation

public enum RankingProvider: String, CaseIterable, Codable, Identifiable {
    case douban, rottenTomatoes
    public var id: String { rawValue }
    public var title: String { self == .douban ? "豆瓣" : "烂番茄" }
    public var categories: [RankingCategory] { self == .douban ? RankingCategory.all : RankingCategory.rottenTomatoes }
}

/// Editorial metadata is separate from playable source records.
public struct RankingCategory: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let type: String
    public let tag: String
    public let provider: RankingProvider
    public init(id: String, title: String, type: String, tag: String, provider: RankingProvider = .douban) {
        self.id = id; self.title = title; self.type = type; self.tag = tag; self.provider = provider
    }
    public var collectionID: String {
        switch id {
        case "movie": return "movie_hot_gaia"
        case "tv": return "tv_hot"
        case "variety": return "tv_variety_show"
        default: return "tv_animation"
        }
    }
    public var pageURL: URL {
        if provider == .rottenTomatoes { return URL(string: "https://www.rottentomatoes.com/browse/" + type + "/sort:popular")! }
        return URL(string: "https://m.douban.com/subject_collection/" + collectionID)!
    }
    public static let rottenTomatoes: [RankingCategory] = [
        .init(id: "rt-streaming", title: "热门流媒体电影", type: "movies_at_home", tag: "popular", provider: .rottenTomatoes),
        .init(id: "rt-theaters", title: "院线热映", type: "movies_in_theaters", tag: "popular", provider: .rottenTomatoes),
        .init(id: "rt-tv", title: "热门剧集", type: "tv_series_browse", tag: "popular", provider: .rottenTomatoes)
    ]
    public static let all: [RankingCategory] = [
        .init(id: "movie", title: "热门电影", type: "movie", tag: "热门"),
        .init(id: "tv", title: "热播剧集", type: "tv", tag: "热门"),
        .init(id: "variety", title: "热门综艺", type: "tv", tag: "综艺"),
        .init(id: "animation", title: "热门动漫", type: "tv", tag: "日本动画")
    ]
}

public struct RankedTitle: Identifiable, Hashable {
    public let video: Video
    public let subjectURL: URL
    public let score: String
    public var id: String { video.id }
}

public struct RankingResult: Identifiable {
    public let category: RankingCategory
    public let items: [RankedTitle]
    public let fetchedAt: Date
    public var id: String { category.id }
}

public struct RankingClient {
    private let client: TVClient
    public init(client: TVClient = TVClient()) { self.client = client }
    public func fetch(_ category: RankingCategory) async throws -> RankingResult {
        if category.provider == .rottenTomatoes {
            let (data, _) = try await client.fetch(category.pageURL, limit: 4 * 1024 * 1024)
            return RankingResult(category: category, items: try Self.parseRottenTomatoes(data), fetchedAt: Date())
        }
        let url = try URLTools.apiURL("https://m.douban.com/rexxar/api/v2/subject_collection/" + category.collectionID + "/items", parameters: ["start": "0", "count": "24"])
        var request = URLRequest(url: url)
        request.setValue("MacTVBOX/0.3 (macOS; public catalog reader)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        let (data, _) = try await client.fetch(request, limit: 2 * 1024 * 1024)
        return RankingResult(category: category, items: try Self.parseCollection(data), fetchedAt: Date())
    }
    public static func parseCollection(_ data: Data) throws -> [RankedTitle] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["subject_collection_items"] as? [[String: Any]] else {
            throw TVError.message("豆瓣片单暂不可读取（接口变化、验证或非 JSON 响应）。可直接搜索影片，或打开来源网页。")
        }
        var seen = Set<String>()
        return items.compactMap { item in
            let id = (item["id"] as? String) ?? (item["id"] as? NSNumber)?.stringValue ?? ""
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }), seen.insert(id).inserted,
                  let title = item["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let url = URL(string: "https://movie.douban.com/subject/" + id + "/") else { return nil }
            let rating = item["rating"] as? [String: Any]
            let value = (rating?["value"] as? NSNumber)?.doubleValue ?? 0
            let score = value > 0 && value <= 10 ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) : ""
            let cover = item["cover"] as? [String: Any], pic = item["pic"] as? [String: Any]
            let poster = (cover?["url"] as? String) ?? (pic?["large"] as? String) ?? (pic?["normal"] as? String) ?? ""
            let year = (item["year"] as? String) ?? (item["year"] as? NSNumber)?.stringValue ?? ""
            let video = Video(id: "douban:" + id, title: title, poster: poster,
                remarks: score.isEmpty ? "暂无评分" : "豆瓣 " + score, year: year,
                director: (item["directors"] as? [String] ?? []).joined(separator: " / "),
                actors: (item["actors"] as? [String] ?? []).joined(separator: " / "),
                summary: item["card_subtitle"] as? String ?? "")
            return RankedTitle(video: video, subjectURL: url, score: score)
        }
    }
    public static func parse(_ data: Data) throws -> [RankedTitle] {
        struct Envelope: Decodable { let subjects: [Subject] }
        struct Subject: Decodable {
            let id: String; let title: String; let cover: String?; let rate: String?; let url: String; let episodes_info: String?
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw TVError.message("豆瓣片单暂不可读取（接口变化、验证或非 JSON 响应）。可直接搜索影片，或打开来源网页。") }
        var seen = Set<String>()
        return envelope.subjects.compactMap { item in
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(item.id).inserted,
                  let url = try? URLTools.httpURL(item.url), url.host == "movie.douban.com", url.path.hasPrefix("/subject/") else { return nil }
            let score = item.rate ?? ""
            let video = Video(id: "douban:" + item.id, title: item.title, poster: item.cover ?? "", remarks: score.isEmpty ? (item.episodes_info ?? "暂无评分") : "豆瓣 \(score)")
            return RankedTitle(video: video, subjectURL: url, score: score)
        }
    }
}

public struct SourceMatch: Identifiable, Hashable {
    public let video: Video
    public let source: Source
    public var id: String { source.key + "|" + video.id }
    public init(video: Video, source: Source) { self.video = video; self.source = source }
}

public struct TitleGroup: Identifiable {
    public let id: String
    public var video: Video
    public var matches: [SourceMatch]
    public var sourceCount: Int { Set(matches.map { $0.source.key }).count }
}

public enum TitleMatcher {
    /// Do not strip season numbers, languages, director cuts or years: those can be different works.
    public static func normalized(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) })
    }
    public static func relevance(_ title: String, query: String) -> Int {
        let title = normalized(title), query = normalized(query)
        guard !query.isEmpty else { return 0 }
        if title == query { return 100 }
        if title.hasPrefix(query) { return 80 }
        if title.contains(query) { return 60 }
        return 0
    }
    public static func key(_ video: Video) -> String { normalized(video.title) + "|" + video.year.trimmingCharacters(in: .whitespaces) }
    public static func groups(_ hits: [SourceMatch]) -> [TitleGroup] {
        var groups: [TitleGroup] = [], indices: [String: Int] = [:], seen = Set<String>()
        for hit in hits where seen.insert(hit.id).inserted {
            let key = hit.source.contentRole.rawValue + "|" + key(hit.video)
            if let index = indices[key] { groups[index].matches.append(hit) }
            else { indices[key] = groups.count; groups.append(TitleGroup(id: key, video: hit.video, matches: [hit])) }
        }
        return groups.sorted { $0.id < $1.id }
    }
    public static func confidence(_ candidate: Video, for target: Video) -> Int {
        guard normalized(candidate.title) == normalized(target.title) else { return 0 }
        if !target.year.isEmpty && !candidate.year.isEmpty { return target.year == candidate.year ? 3 : 1 }
        return 2
    }
    public static func matchLabel(_ candidate: Video, for target: Video) -> String {
        switch confidence(candidate, for: target) {
        case 3: return "同名 · 年份相符"
        case 2: return "同名 · 年份待核对"
        case 1: return "同名但年份不同 · 请核对版本"
        default: return "近似搜索结果 · 请核对片名"
        }
    }
}
