import Foundation

public enum ConfigurationParser {
    public static func parse(_ data: Data, baseURL: URL? = nil) throws -> TVConfiguration {
        guard data.count <= 8 * 1024 * 1024 else { throw TVError.message("配置超过 8 MB，已拒绝载入。") }
        guard var text = String(data: data, encoding: .utf8) else { throw TVError.message("配置不是 UTF-8 文本。") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        var warnings: [String] = []
        // A narrowly scoped, reported repair for the supplied provider's broken ext keys.
        // Valid JSON strings cannot contain raw newlines; only a standalone field is matched.
        let pattern = #"(?m)^(\s*)ext"\s*:"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var repaired = 0
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text), let indent = Range(match.range(at: 1), in: text) else { continue }
            text.replaceSubrange(range, with: String(text[indent]) + "\"ext\":")
            repaired += 1
        }
        if repaired > 0 { warnings.append("上游配置有 \(repaired) 处 ext 字段缺少起始引号，已进行局部修复；未修改接口内容。") }
        text = removeTrailingCommas(stripComments(text))
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: Data(text.utf8)) }
        catch { throw TVError.message("配置 JSON 无法解析：\(error.localizedDescription) 请检查是否为配置文件而非网页。") }
        guard let root = object as? [String: Any], let sites = root["sites"] as? [[String: Any]] else {
            throw TVError.message("没有找到 TVBox 的 sites 列表。如果这是影视采集接口，请使用“添加接口”。")
        }
        var sources: [Source] = []
        var seen = Set<String>()
        for (index, item) in sites.enumerated() {
            guard let api = item["api"] as? String, !api.isEmpty else {
                warnings.append("第 \(index + 1) 个源缺少 api，已跳过。")
                continue
            }
            let key = scalar(item["key"]).isEmpty ? "source-\(index)" : scalar(item["key"])
            guard seen.insert(key).inserted else { warnings.append("重复的源标识 \(key) 已跳过。"); continue }
            let type = Int(scalar(item["type"])) ?? -1
            let name = scalar(item["name"])
            sources.append(Source(key: key, name: name.isEmpty ? key : name, type: type,
                                  api: URLTools.resolved(api, relativeTo: baseURL),
                                  searchable: scalar(item["searchable"]) != "0",
                                  ext: try item["ext"].map { try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed])) },
                                  jar: item["jar"] as? String))
        }
        guard !sources.isEmpty else { throw TVError.message("配置中没有有效的源。") }
        if sources.allSatisfy({ !$0.isSupported }) {
            warnings.append("当前配置没有已适配的原生协议或有效 HTTP 运行时接口。导入成功不代表其中的 Spider 插件可在 macOS 上运行。")
        }
        return TVConfiguration(sources: sources, spider: root["spider"] as? String, warnings: warnings)
    }

    static func scalar(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    // JSONC support without breaking http:// strings, escaped quotes, or line positions.
    static func stripComments(_ text: String) -> String {
        let chars = Array(text)
        var result = "", i = 0, quoted = false, escaped = false
        while i < chars.count {
            let c = chars[i]
            if quoted {
                result.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
                i += 1; continue
            }
            if c == "\"" { quoted = true; result.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { result.append(" "); i += 1 }
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                result += "  "; i += 2
                while i < chars.count {
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" { result += "  "; i += 2; break }
                    result.append(chars[i] == "\n" ? "\n" : " "); i += 1
                }
            } else { result.append(c); i += 1 }
        }
        return result
    }

    static func removeTrailingCommas(_ text: String) -> String {
        let chars = Array(text)
        var result = "", quoted = false, escaped = false
        for i in chars.indices {
            let c = chars[i]
            if quoted {
                result.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
            } else if c == "\"" { quoted = true; result.append(c) }
            else if c == "," {
                var j = i + 1
                while j < chars.count && chars[j].isWhitespace { j += 1 }
                if j == chars.count || (chars[j] != "]" && chars[j] != "}") { result.append(c) }
            } else { result.append(c) }
        }
        return result
    }
}
