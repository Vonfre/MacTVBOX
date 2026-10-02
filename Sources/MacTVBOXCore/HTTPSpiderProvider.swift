import Foundation

/// TVBox type=4 / drpy-node style HTTP contract. The server owns its runtime;
/// Managed Android execution is isolated in a separate emulator, never in this process.
public struct HTTPSpiderProvider {
    let client: TVClient
    let source: Source
    var endpoint: String { source.bridgeURL ?? source.api }
    public init(client: TVClient = TVClient(), source: Source) { self.client = client; self.source = source }

    public func browse(category: String? = nil, page: Int = 1, query: String? = nil) async throws -> VideoPage {
        var parameters = ["pg": String(max(1, page))]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parameters["wd"] = query.trimmingCharacters(in: .whitespacesAndNewlines); parameters["quick"] = "0"
        } else if let category, !category.isEmpty { parameters["ac"] = "detail"; parameters["t"] = category }
        let (data, url) = try await client.fetch(URLTools.apiURL(endpoint, parameters: parameters))
        return try Self.parsePage(data, baseURL: url)
    }
    public func detail(id: String) async throws -> Video {
        let (data, url) = try await client.fetch(URLTools.apiURL(endpoint, parameters: ["ac": "detail", "ids": id]))
        let result = try Self.parsePage(data, baseURL: url)
        guard let video = result.videos.first(where: { $0.id == id }) else { throw TVError.message("运行时没有返回该影片详情。") }
        return video
    }
    public func resolve(_ episode: Episode) async throws -> ResolvedMedia {
        guard let resolution = episode.resolution, resolution.parseType == "http-spider" else {
            throw TVError.message("这条记录缺少运行时线路信息，请重新打开影片详情后选集。")
        }
        let url = try URLTools.apiURL(endpoint, parameters: ["play": episode.address, "flag": resolution.parser])
        let (data, _) = try await client.fetch(url, limit: 2 * 1024 * 1024)
        return try Self.parsePlayer(data)
    }
    public static func parsePage(_ data: Data, baseURL: URL) throws -> VideoPage {
        guard data.count <= 12 * 1024 * 1024,
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TVError.message("运行时返回的不是 TVBox HTTP JSON。")
        }
        try rejectBridgeError(root)
        // Home responses may contain only class. Never turn an arbitrary error into an empty page.
        if root["list"] == nil, root["class"] is [[String: Any]] { root["list"] = [[String: Any]]() }
        let normalized = try JSONSerialization.data(withJSONObject: root)
        var page = try VODParser.parse(normalized, baseURL: baseURL, preserveEpisodeAddresses: true)
        let rawItems = root["list"] as? [[String: Any]] ?? []
        for vi in page.videos.indices {
            guard let raw = rawItems.first(where: { ConfigurationParser.scalar($0["vod_id"]) == page.videos[vi].id }) else { continue }
            let flags = ConfigurationParser.scalar(raw["vod_play_from"]).components(separatedBy: "$$$")
            let groups = ConfigurationParser.scalar(raw["vod_play_url"]).components(separatedBy: "$$$")
            // Empty groups are omitted by VODParser. Keep original flag indices, including duplicate flags.
            var lineIndex = 0
            for (index, group) in groups.enumerated() {
                guard !VODParser.parseLines(from: "", urls: group).isEmpty else { continue }
                guard lineIndex < page.videos[vi].lines.count else { break }
                let flag = index < flags.count ? flags[index] : ""
                for ei in page.videos[vi].lines[lineIndex].episodes.indices {
                    page.videos[vi].lines[lineIndex].episodes[ei].resolution = EpisodeResolution(parser: flag, parseType: "http-spider", token: "", headers: [:])
                }
                lineIndex += 1
            }
        }
        return page
    }
    public static func parsePlayer(_ data: Data) throws -> ResolvedMedia {
        guard data.count <= 2 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TVError.message("运行时播放响应无效。") }
        try rejectBridgeError(root)
        guard ConfigurationParser.scalar(root["parse"]) == "0",
              root["jx"] == nil || ConfigurationParser.scalar(root["jx"]) == "0" else {
            throw TVError.message("运行时返回网页嗅探 / 二次解析任务，而非媒体直链。请让服务端完成解析并返回 parse=0；本机不会执行网页脚本或绕过验证。")
        }
        let address = ConfigurationParser.scalar(root["url"])
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TVError.message("插件执行完成，但上游返回空播放地址。此线路当前不可用，请尝试其他线路；这不是缺少 Android 运行时。") }
        guard ConfigurationParser.scalar(root["playUrl"]).isEmpty else { throw TVError.message("此线路仍需网页二次解析，尚未返回可供播放器使用的媒体地址。") }
        let url = try URLTools.httpURL(address)
        guard !["html", "htm"].contains(url.pathExtension.lowercased()) else { throw TVError.message("运行时返回了网页，不是媒体直链。") }
        var headerObject: Any? = root["header"] ?? root["headers"]
        if let text = headerObject as? String { headerObject = try JSONSerialization.jsonObject(with: Data(text.utf8)) }
        var headers: [String: String] = [:]
        if let object = headerObject {
            guard let values = object as? [String: String], values.count <= 32 else { throw TVError.message("运行时请求头格式无效。") }
            let forbidden: Set<String> = ["host", "content-length", "connection", "transfer-encoding"]
            for (key, value) in values {
                guard !key.isEmpty, key.utf8.count <= 128, value.utf8.count <= 8192,
                      key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                      value.unicodeScalars.allSatisfy({ $0.value == 9 || ($0.value >= 32 && $0.value != 127) }), !forbidden.contains(key.lowercased()) else {
                    throw TVError.message("运行时返回不安全的请求头，已拒绝播放。")
                }
                headers[key] = value
            }
        }
        return ResolvedMedia(url: url, headers: headers)
    }
    private static func rejectBridgeError(_ root: [String: Any]) throws {
        if let message = root["bridge_error"] as? String { throw TVError.message(String(message.prefix(600))) }
    }

}
