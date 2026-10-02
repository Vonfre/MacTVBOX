import XCTest
@testable import MacTVBOXCore

private final class ExpansionFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let (code, data) = try Self.response(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    static func json(_ object: [String: Any]) throws -> (Int, Data) { (200, try JSONSerialization.data(withJSONObject: object)) }
    static func response(_ request: URLRequest) throws -> (Int, Data) {
        let url = request.url!, path = url.path, host = url.host ?? ""
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? { query.first { $0.name == name }?.value }
        if host == "rj.fixture.test" {
            guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=MacTVBOX-") == true else { throw TVError.message("RJ body type") }
            let text = String(decoding: body(request), as: UTF8.self)
            guard let timestamp = Dm84SpiderProvider.matches("name=\"timestamp\"\\r\\n\\r\\n([0-9]+)", text).first?[1],
                  text.contains(SpiderCrypto.md5(LegacyAppSpiderProvider.rjSalt + timestamp).lowercased()) else { throw TVError.message("RJ signature") }
            let video: [String: Any] = ["vod_id": 12, "vod_name": "测试"]
            if path == "/v3/type/top_type" { return try json(["code": 1, "data": ["list": [["type_id": 1, "type_name": "电影"]]]]) }
            if path == "/v3/home/vod_details" {
                var detail = video
                detail["vod_play_list"] = [["name": "公开", "parse_urls": ["https://parser.fixture.test/?url="], "urls": [["name": "01", "url": "opaque"]]]]
                return try json(["code": 1, "data": detail])
            }
            if path == "/v3/home/search", !text.contains("片名 + & 中文") { throw TVError.message("RJ keyword") }
            return try json(["code": 1, "data": ["list": [video]]])
        }
        if host == "parser.fixture.test" {
            guard param("url") == "opaque", param("sign") != nil, param("timestamp") != nil else { throw TVError.message("RJ parser parameters") }
            return try json(["url": "https://cdn.fixture.test/movie.m3u8"])
        }
        if ["qi.fixture.test", "qi404.fixture.test", "qiempty.fixture.test"].contains(host) {
            if host == "qi404.fixture.test" { return (404, Data("Not found".utf8)) }
            let data: [String: Any]
            if path.hasSuffix("vodParse") {
                guard request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded" else { throw TVError.message("Qi player body type") }
                let form = String(decoding: body(request), as: UTF8.self)
                guard form.contains("token=fixture%2Btoken"), form.contains("url=opaque") else { throw TVError.message("Qi player parameters") }
                data = ["json": "{\"url\":\"https://cdn.fixture.test/movie.mp4\"}"]
            } else {
                guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8", let params = try JSONSerialization.jsonObject(with: body(request)) as? [String: String] else { throw TVError.message("Qi request JSON") }
                let video: [String: Any] = ["vod_id": 12, "vod_name": "测试"]
                if path.hasSuffix("vodDetail") {
                    guard params["vod_id"] == "12" else { throw TVError.message("Qi ID") }
                    data = ["vod": video, "vod_play_list": [["player_info": ["show": "高清", "parse": "fixture"], "urls": [["name": "01", "url": "opaque", "token": "fixture+token"]]]]]
                } else if path.hasSuffix("searchList") {
                    guard params["keywords"] == "片名 + & 中文" else { throw TVError.message("Qi query") }; data = ["search_list": [video]]
                } else if host == "qiempty.fixture.test", path.hasSuffix("initV120") {
                    data = ["type_list": [["type_id": 1, "type_name": "电影"]], "recommend_list": []]
                } else {
                    if host == "qiempty.fixture.test" {
                        guard path.hasSuffix("typeFilterVodList"), params["type_id"] == "1", param("page") == "1" else { throw TVError.message("Qi empty home fallback") }
                    }
                    data = ["type_list": [["type_id": 1, "type_name": "电影"]], "recommend_list": [video]]
                }
            }
            let key = Data("0123456789abcdef".utf8)
            let encrypted = try AppGetProvider.aes(JSONSerialization.data(withJSONObject: data), key: key, iv: key, encrypt: true)
            return try json(["code": 1, "data": encrypted.base64EncodedString()])
        }
        if host == "jpys.fixture.test" {
            let params = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
            let timestamp = request.value(forHTTPHeaderField: "t") ?? ""
            guard request.value(forHTTPHeaderField: "sign") == JpysSpiderProvider.signature(params, timestamp: timestamp), request.value(forHTTPHeaderField: "deviceId") != nil, request.value(forHTTPHeaderField: "authorization") == nil else { throw TVError.message("Jpys signature/identity") }
            let video: [String: Any] = ["vodId": 12, "vodName": "测试", "vodYear": "2026"]
            if path.hasSuffix("/detail") {
                var data = video; data["episodeList"] = [["nid": 102, "name": "02", "sort": 2], ["nid": 101, "name": "01", "sort": 1]]
                return try json(["code": 200, "data": data])
            }
            if path.hasSuffix("/episode/url") {
                guard param("id") == "12", param("nid") == "101" else { throw TVError.message("Jpys episode identity") }
                return try json(["code": 200, "data": ["list": [["needLogin": true, "flag": false, "resolution": 1080, "url": "https://cdn.fixture.test/restricted.m3u8"], ["needLogin": false, "flag": true, "resolution": 480, "url": "https://cdn.fixture.test/public.m3u8"]]]])
            }
            let page: [String: Any] = ["list": [video], "totalPage": 3]
            if path.hasSuffix("searchByWord") {
                guard param("keyword") == "片名 + & 中文" else { throw TVError.message("Jpys encoded search") }
                return try json(["code": 200, "data": ["result": page]])
            }
            return try json(["code": 200, "data": page])
        }
        if host == "www.tuxiaobei.com" {
            let html = path.hasPrefix("/play/") ? #"<h1>儿歌</h1><script type="application/ld+json">{"contentUrl":"https://cdn.fixture.test/kids.mp4"}</script>"# : "<a href='/play/12' title='儿歌'><img src='/cover.jpg'></a>"
            return (200, Data(html.utf8))
        }
        if host.contains("kugou.com") {
            let hash = String(repeating: "a", count: 32), mv = String(repeating: "b", count: 32)
            if path.hasSuffix("rank/list") { return try json(["status": 1, "data": ["info": [["rankid": 1, "rankname": "榜单"]]]]) }
            if path.hasSuffix("mv.php") { return try json(["mvdata": ["sq": ["downurl": "https://cdn.fixture.test/mv.mp4"]]]) }
            if path.hasSuffix("getSongInfo.php") { return try json(["error": "paid", "songName": "测试曲目"] ) }
            return try json(["status": 1, "data": ["total": 1, "info": [["hash": hash, "mvhash": mv, "filename": "测试曲目"]]]])
        }
        throw TVError.message("Unexpected fixture host/path; never use the real network")
    }
}

final class NativeExpansionTransportTests: XCTestCase {
    private func client() -> TVClient {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ExpansionFixtureProtocol.self]
        return TVClient(session: URLSession(configuration: configuration))
    }
    func testRJFullTransportAndSignedParser() async throws {
        let c = client(), source = Source(key: "rj", name: "rj", type: 3, api: "csp_AppRJ", ext: .string("https://rj.fixture.test"))
        let home = try await c.browse(source: source); XCTAssertEqual(home.categories.count, 1)
        let search = try await c.browse(source: source, query: "片名 + & 中文"); XCTAssertEqual(search.videos.first?.id, "12")
        let detail = try await c.detail(source: source, id: "12")
        let media = try await c.resolve(source: source, episode: detail.lines[0].episodes[0])
        XCTAssertEqual(media.url.path, "/movie.m3u8")
    }
    func testQiFullTransportAESAndFormEncoding() async throws {
        let c = client(), source = Source(key: "qi", name: "qi", type: 3, api: "csp_AppQi", ext: .string("https://qi.fixture.test|0123456789abcdef"))
        let home = try await c.browse(source: source); XCTAssertEqual(home.videos.count, 1)
        let search = try await c.browse(source: source, query: "片名 + & 中文"); XCTAssertEqual(search.videos.first?.id, "12")
        let detail = try await c.detail(source: source, id: "12")
        let media = try await c.resolve(source: source, episode: detail.lines[0].episodes[0])
        XCTAssertEqual(media.url.path, "/movie.mp4")
    }
    func testQiEmptyHomepageUsesReturnedCategory() async throws {
        let c = client(), source = Source(key: "qi", name: "qi", type: 3, api: "csp_AppQi", ext: .string("https://qiempty.fixture.test|0123456789abcdef"))
        let home = try await c.browse(source: source)
        XCTAssertEqual(home.videos.first?.id, "12")
        XCTAssertEqual(home.categories.first?.id, "1")
        XCTAssertEqual(home.categories.first?.name, "电影")
    }
    func testQi404IsNotAnEmptySuccessfulSearch() async throws {
        let source = Source(key: "qi", name: "qi", type: 3, api: "csp_AppQi", ext: .string("https://qi404.fixture.test|0123456789abcdef"))
        do { _ = try await client().browse(source: source, query: "test"); XCTFail("404 treated as empty results") }
        catch let error as HTTPFailure { XCTAssertEqual(error.statusCode, 404) }
    }
    func testJpysFullTransportChoosesOnlyAuthorizedQuality() async throws {
        let c = client(), source = Source(key: "jpys", name: "jpys", type: 3, api: "csp_Jpys", ext: .string("https://jpys.fixture.test"))
        let home = try await c.browse(source: source); XCTAssertEqual(home.pageCount, 3)
        let search = try await c.browse(source: source, query: "片名 + & 中文"); XCTAssertEqual(search.videos.count, 1)
        let detail = try await c.detail(source: source, id: "12")
        XCTAssertEqual(detail.lines[0].episodes.map(\.name), ["01", "02"])
        let media = try await c.resolve(source: source, episode: detail.lines[0].episodes[0])
        XCTAssertEqual(media.url.path, "/public.m3u8")
    }
    func testJpysFailsClosedForUnknownOrRestrictedEntitlements() throws {
        XCTAssertEqual(JpysSpiderProvider.signature(["keyword": "片名 + & 中文", "pageNum": "1"], timestamp: "1700000000000"), "d03ed4fdd9f57b7c52ac33be53f295ef479cd556")
        for row: [String: Any] in [["url": "https://cdn.test/a.mp4"], ["url": "https://cdn.test/a.mp4", "needLogin": true, "flag": true], ["url": "https://cdn.test/a.mp4", "needLogin": false, "flag": false]] {
            XCTAssertThrowsError(try JpysSpiderProvider.publicMedia(["list": [row]], referer: "https://fixture.test"))
        }
        XCTAssertThrowsError(try JpysSpiderProvider.detail(["vodId": 12, "vodName": "测试", "episodeList": []], id: "13"))
        XCTAssertFalse(JpysSpiderProvider.numericID("../12"))
    }
    func testNativeTuXiaoBeiDoesNotFetchTheDeadJS() async throws {
        let c = client(), source = Source(key: "kids", name: "kids", type: 3, api: "http://xn--z7x900a.net/api/drpy2.min.js", ext: .string("./js/兔小贝.js"))
        let search = try await c.browse(source: source, query: "儿歌"); XCTAssertEqual(search.videos.count, 1)
        let detail = try await c.detail(source: source, id: "/play/12")
        let media = try await c.resolve(source: source, episode: detail.lines[0].episodes[0])
        XCTAssertEqual(media.url.path, "/kids.mp4")
    }
    func testKugouMVAndPaidSongHaveSeparateOutcomes() async throws {
        let c = client(), source = Source(key: "music", name: "music", type: 3, api: "csp_Kugou")
        let home = try await c.browse(source: source); XCTAssertEqual(home.videos.first?.id, "rank:1")
        let detail = try await c.detail(source: source, id: "rank:1")
        XCTAssertEqual(detail.lines.first?.name, "MV")
        let media = try await c.resolve(source: source, episode: detail.lines[0].episodes[0]); XCTAssertEqual(media.url.path, "/mv.mp4")
        do { _ = try await c.resolve(source: source, episode: detail.lines[1].episodes[0]); XCTFail("Paid track accepted") }
        catch let error as SpiderFailure { if case .authentication = error {} else { XCTFail("Incorrect paid-track error") } }
    }
}
