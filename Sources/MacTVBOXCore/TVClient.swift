import Foundation

public final class TVClient {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 40
            config.httpAdditionalHeaders = ["User-Agent": "MacTVBOX/0.3 (macOS)", "Accept": "application/json, application/xml, text/plain, */*"]
            self.session = URLSession(configuration: config)
        }
    }
    public func configuration(at address: String) async throws -> TVConfiguration {
        let url = try URLTools.httpURL(address)
        let (data, finalURL) = try await fetch(url, limit: 8 * 1024 * 1024)
        return try ConfigurationParser.parse(data, baseURL: finalURL)
    }
    public func browse(source: Source, category: String? = nil, page: Int = 1, query: String? = nil) async throws -> VideoPage {
        guard source.isSupported else { throw TVError.message(source.compatibilityNote) }
        if source.usesHTTPSpider { return try await HTTPSpiderProvider(client: self, source: source).browse(category: category, page: page, query: query) }
        if source.isAppGet { return try await AppGetProvider(client: self, source: source).browse(category: category, page: page, query: query) }
        var parameters = ["ac": source.type == 0 ? "videolist" : "detail", "pg": String(page)]
        if let category, !category.isEmpty { parameters["t"] = category }
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parameters["wd"] = query.trimmingCharacters(in: .whitespacesAndNewlines) }
        let url = try URLTools.apiURL(source.api, parameters: parameters)
        let (data, finalURL) = try await fetch(url)
        return try VODParser.parse(data, baseURL: finalURL)
    }
    public func detail(source: Source, id: String) async throws -> Video {
        guard source.isSupported else { throw TVError.message(source.compatibilityNote) }
        if source.usesHTTPSpider { return try await HTTPSpiderProvider(client: self, source: source).detail(id: id) }
        if source.isAppGet { return try await AppGetProvider(client: self, source: source).detail(id: id) }
        let url = try URLTools.apiURL(source.api, parameters: ["ac": source.type == 0 ? "videolist" : "detail", "ids": id])
        let (data, finalURL) = try await fetch(url)
        let page = try VODParser.parse(data, baseURL: finalURL)
        guard let video = page.videos.first(where: { $0.id == id }) else { throw TVError.message("接口没有返回该影片的详情。") }
        return video
    }
    public func resolve(source: Source, episode: Episode) async throws -> ResolvedMedia {
        if source.usesHTTPSpider { return try await HTTPSpiderProvider(client: self, source: source).resolve(episode) }
        if source.isAppGet { return try await AppGetProvider(client: self, source: source).resolve(episode) }
        return ResolvedMedia(url: try URLTools.httpURL(episode.address), headers: [:])
    }
    public func fetch(_ url: URL, limit: Int = 12 * 1024 * 1024) async throws -> (Data, URL) {
        return try await fetch(URLRequest(url: url), limit: limit)
    }
    public func fetch(_ request: URLRequest, limit: Int = 12 * 1024 * 1024) async throws -> (Data, URL) {
        guard let url = request.url else { throw TVError.message("无效的请求地址。") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TVError.message("服务器返回 HTTP \(code)。请检查地址或稍后重试。")
        }
        guard response.expectedContentLength <= limit else { throw TVError.message("服务器返回内容过大，已中止。") }
        var data = Data()
        for try await byte in bytes {
            if data.count % 65536 == 0 { try Task.checkCancellation() }
            guard data.count < limit else { throw TVError.message("服务器返回内容超过安全大小限制。") }
            data.append(byte)
        }
        return (data, response.url ?? url)
    }
}
