import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum VODParser {
    public static func parse(_ data: Data, baseURL: URL? = nil, preserveEpisodeAddresses: Bool = false) throws -> VideoPage {
        guard data.count <= 12 * 1024 * 1024 else { throw TVError.message("接口响应超过 12 MB。") }
        let prefix = String(decoding: data.prefix(100), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.hasPrefix("<") { return try parseXML(data, baseURL: baseURL) }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw TVError.message("影视接口返回的不是有效 JSON / XML：\(error.localizedDescription)") }
        guard let root = object as? [String: Any], let list = root["list"] as? [[String: Any]] else {
            throw TVError.message("接口缺少 list 字段；目前支持苹果 CMS 风格的标准 JSON / XML 接口。")
        }
        let categories = (root["class"] as? [[String: Any]] ?? []).compactMap { item -> Category? in
            let id = scalar(item["type_id"]), name = scalar(item["type_name"])
            return id.isEmpty || name.isEmpty ? nil : Category(id: id, name: name)
        }
        var seen = Set<String>()
        let videos = list.compactMap { item -> Video? in
            let id = scalar(item["vod_id"]), title = scalar(item["vod_name"])
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { return nil }
            return Video(id: id, title: cleanText(title), poster: URLTools.resolved(scalar(item["vod_pic"]), relativeTo: baseURL),
                         remarks: scalar(item["vod_remarks"]), year: scalar(item["vod_year"]), area: scalar(item["vod_area"]),
                         genre: scalar(item["type_name"]), director: scalar(item["vod_director"]), actors: scalar(item["vod_actor"]),
                         summary: cleanText(scalar(item["vod_content"])),
                         lines: parseLines(from: scalar(item["vod_play_from"]), urls: scalar(item["vod_play_url"]), baseURL: baseURL, preserveAddresses: preserveEpisodeAddresses))
        }
        return VideoPage(videos: videos, categories: uniqueCategories(categories), page: max(1, Int(scalar(root["page"])) ?? 1), pageCount: max(1, Int(scalar(root["pagecount"])) ?? 1))
    }

    public static func parseLines(from: String, urls: String, baseURL: URL? = nil, preserveAddresses: Bool = false) -> [PlayLine] {
        let names = from.components(separatedBy: "$$$")
        var lines: [PlayLine] = []
        for (lineIndex, group) in urls.components(separatedBy: "$$$").enumerated() {
            var seen = Set<String>()
            let episodes = group.components(separatedBy: "#").enumerated().compactMap { index, entry -> Episode? in
                let pair = entry.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
                let address = String(pair.last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !address.isEmpty else { return nil }
                let title = pair.count > 1 ? String(pair[0]) : "第 \(index + 1) 集"
                let episode = Episode(name: title.isEmpty ? "第 \(index + 1) 集" : title, address: preserveAddresses ? address : URLTools.resolved(address, relativeTo: baseURL))
                return seen.insert(episode.id).inserted ? episode : nil
            }
            guard !episodes.isEmpty else { continue }
            let rawName = lineIndex < names.count && !names[lineIndex].isEmpty ? names[lineIndex] : "线路"
            // Index suffix keeps SwiftUI identities stable for duplicate line names.
            lines.append(PlayLine(name: "\(rawName) · \(lineIndex + 1)", episodes: episodes))
        }
        return lines
    }

    public static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scalar(_ value: Any?) -> String { ConfigurationParser.scalar(value) }
    private static func uniqueCategories(_ categories: [Category]) -> [Category] {
        var seen = Set<String>()
        return categories.filter { seen.insert($0.id).inserted }
    }
    private static func parseXML(_ data: Data, baseURL: URL?) throws -> VideoPage {
        // Reject DTDs, including internal entity expansion; external entities are disabled too.
        let text = String(decoding: data, as: UTF8.self)
        guard !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else {
            throw TVError.message("为安全起见，不接受包含 DTD / ENTITY 的 XML。")
        }
        let delegate = VODXMLDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.hasList else { throw TVError.message("XML 接口格式无效或缺少 list 节点。") }
        return VideoPage(videos: delegate.videos, categories: uniqueCategories(delegate.categories), page: delegate.page, pageCount: delegate.pageCount)
    }
}

private final class VODXMLDelegate: NSObject, XMLParserDelegate {
    let baseURL: URL?
    var videos: [Video] = [], categories: [Category] = []
    var page = 1, pageCount = 1, hasList = false
    private var current: [String: String]?
    private var lines: [PlayLine] = []
    private var buffer = "", lineName = "", categoryID: String?
    private var seen = Set<String>()
    init(baseURL: URL?) { self.baseURL = baseURL }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        buffer = ""
        switch elementName {
        case "list":
            hasList = true; page = max(1, Int(attributes["page"] ?? "") ?? 1); pageCount = max(1, Int(attributes["pagecount"] ?? "") ?? 1)
        case "video": current = [:]; lines = []
        case "ty": if current == nil { categoryID = attributes["id"] }
        case "dd": lineName = attributes["flag"] ?? "线路"
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { buffer += String(decoding: CDATABlock, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "ty", let id = categoryID {
            categories.append(Category(id: id, name: value)); categoryID = nil
        } else if elementName == "dd", current != nil {
            let episodes = VODParser.parseLines(from: lineName, urls: value, baseURL: baseURL).flatMap(\.episodes)
            if !episodes.isEmpty { lines.append(PlayLine(name: "\(lineName) · \(lines.count + 1)", episodes: episodes)) }
        } else if elementName == "video", let item = current {
            if let id = item["id"], let title = item["name"], seen.insert(id).inserted {
                videos.append(Video(id: id, title: title, poster: URLTools.resolved(item["pic"] ?? "", relativeTo: baseURL),
                                    remarks: item["note"] ?? item["state"] ?? "", year: item["year"] ?? "", area: item["area"] ?? "",
                                    genre: item["type"] ?? "", director: item["director"] ?? "", actors: item["actor"] ?? "",
                                    summary: VODParser.cleanText(item["des"] ?? ""), lines: lines))
            }
            current = nil
        } else if current != nil { current?[elementName] = value }
        buffer = ""
    }
}
