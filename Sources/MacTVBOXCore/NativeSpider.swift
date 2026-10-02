import Foundation

/// Explicit, audited protocol adapters, not a JAR/DEX or arbitrary JS interpreter.
public enum NativeSpider: String, CaseIterable {
    case jpys = "csp_Jpys"
    case jianpian = "csp_Jianpian"
    case guazi = "csp_Gz360"
    case bili = "csp_Bili"
    case dm84 = "csp_Dm84"
    case firstAid = "csp_FirstAid"
    case trailers = "csp_YGP"
    case tuxiaobei = "native_TuXiaoBei"
    case kanqiu = "csp_Kanqiu"
    case kugou = "csp_Kugou"
    case appRJ = "csp_AppRJ"
    case appQi = "csp_AppQi"

    public var label: String {
        switch self {
        case .jpys: return "Jpys 原生适配"
        case .jianpian: return "荐片原生适配"
        case .guazi: return "瓜子原生适配"
        case .bili: return "B站原生插件"
        case .dm84: return "动漫84原生插件"
        case .appRJ: return "AppRJ 原生适配"
        case .appQi: return "AppQi 原生适配"
        case .kugou: return "酷狗原生适配"
        case .firstAid: return "急救科普原生适配"
        case .trailers: return "预告片原生适配"
        case .tuxiaobei: return "兔小贝原生适配"
        case .kanqiu: return "看球原生适配"
        }
    }
    public var note: String {
        switch self {
        case .jpys: return "移植当前站点公开 HTTP 协议、搜索与选集；仅播放明确允许访客使用的清晰度，不执行远程 JS，不使用登录限定线路。"
        case .appRJ: return "原生签名请求、搜索、选集与 JSON 解析；解析器失效或需要授权时明确报错，接入不等于已验证播放。"
        case .appQi: return "原生 AES 协议、分类、搜索、选集与解析；当前订阅搜索可能返回 404，可先浏览分类；空线路、失效解析会明确报错。"
        case .kugou: return "公开榜单、搜索与音乐 / MV 播放；付费、登录及版权限制明确报错，不绕过授权。"
        case .firstAid: return "公开急救栏目与视频直链；搜索仅覆盖急救目录，不代替专业医疗指导。"
        case .trailers: return "公开电影预告片搜索、详情与播放，不提供电影正片。"
        case .tuxiaobei: return "独立移植兔小贝公开儿歌、故事、国学目录及播放；搜索仅覆盖公开目录，并非通用 JS 运行时。"
        case .kanqiu: return "原生赛事目录与公开直播直链；仅显示未加锁线路，赛事未开始或过期可能无法播放。"
        case .jianpian: return "macOS 原生搜索、分类、详情与 HTTP 视频播放；不需要 Android。专有 FTP/P2P 不支持。"
        case .guazi: return "macOS 原生会话、搜索、选集、分清晰度线路与播放解析；不需要 Android，上游限制会明确报错。"
        case .bili: return "已实现分类、搜索、分P和公开 MP4 解析；仅使用账户有权访问的内容，登录限制 / 风控会明确报错。"
        case .dm84: return "已实现分类、搜索、选集和已知网页解析协议；不执行远程脚本，不绕过验证码，其他解析器会明确报错。"
        }
    }
}

public enum SourceRequirement: String, CaseIterable {
    case native = "原生适配"
    case bridge = "HTTP 运行时"
    case utility = "工具 / 元数据"
    case cloud = "网盘授权 / 待适配"
    case javascript = "JS 规则 / 待适配"
    case unadapted = "待原生适配"
    case invalid = "无效接口"
}

/// Keeps supplementary content out of feature-film source matching.
public enum SourceContentRole: String {
    case video, trailer, music, sports, education, children
}

public extension Source {
    var contentRole: SourceContentRole {
        switch nativeSpider {
        case .trailers: return .trailer
        case .kugou: return .music
        case .kanqiu: return .sports
        case .firstAid: return .education
        case .tuxiaobei: return .children
        default: return .video
        }
    }

    var nativeSpider: NativeSpider? {
        guard type == 3 else { return nil }
        if api == "http://xn--z7x900a.net/api/drpy2.min.js", ext?.string == "./js/兔小贝.js" { return .tuxiaobei }
        return NativeSpider(rawValue: api)
    }
    var requirement: SourceRequirement {
        if usesHTTPSpider { return .bridge }
        if isSupported { return .native }
        if type == 3 {
            if ["csp_Config", "csp_Push", "csp_Douban"].contains(api) { return .utility }
            if ["csp_Duopan", "csp_MiSou", "csp_PanSearch"].contains(api) { return .cloud }
            if api.lowercased().contains(".js") { return .javascript }
            return .unadapted
        }
        return .invalid
    }
}

/// Typed diagnostic stages keep network / authentication failures distinct from lack of an adapter.
public enum SpiderFailure: LocalizedError {
    case configuration(String), upstream(String), authentication(String), format(String), player(String)
    public var errorDescription: String? {
        switch self {
        case .configuration(let text): return "插件配置：" + text
        case .upstream(let text): return "上游接口：" + text
        case .authentication(let text): return "登录 / 验证：" + text
        case .format(let text): return "协议已变化：" + text
        case .player(let text): return "播放解析：" + text
        }
    }
}

/// Bili collections differ only in browse categories. Keyword requests share an API;
/// perform them once per credential scope, then attribute the results to each source.
public enum SourceSearch {
    public static func groups(_ sources: [Source]) -> [[Source]] {
        var result: [[Source]] = [], biliGroups: [String: Int] = [:]
        for source in sources where source.isSupported && source.searchable {
            guard source.nativeSpider == .bili, !source.usesHTTPSpider else { result.append([source]); continue }
            let credential = BiliSpiderProvider.options(for: source)["cookie"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let index = biliGroups[credential] { result[index].append(source) }
            else { biliGroups[credential] = result.count; result.append([source]) }
        }
        return result
    }
}
