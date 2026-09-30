import Foundation

public enum URLTools {
    public static let defaultConfiguration = "http://肥猫.net"
    public static func httpURL(_ raw: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw TVError.message("请输入完整的 http:// 或 https:// 地址；不支持内嵌账号密码。")
        }
        return url
    }

    public static func apiURL(_ raw: String, parameters: [String: String]) throws -> URL {
        let url = try httpURL(raw)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw TVError.message("接口地址格式不正确。")
        }
        // Drop stale request parameters but preserve provider-specific tokens.
        let requestKeys: Set<String> = ["ac", "wd", "pg", "t", "ids", "play", "flag", "quick", "refresh", "action", "value"]
        var items = (parts.queryItems ?? []).filter { !requestKeys.contains($0.name) }
        items += parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        parts.queryItems = items
        // Form-style HTTP servers decode raw + as space; URLQueryItem leaves it unescaped.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let result = parts.url else { throw TVError.message("无法生成接口请求。") }
        return result
    }

    public static func resolved(_ address: String, relativeTo base: URL?) -> String {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { return (base?.scheme ?? "https") + ":" + value }
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return URL(string: value, relativeTo: base)?.absoluteURL.absoluteString ?? value
        }
        return value
    }
}
