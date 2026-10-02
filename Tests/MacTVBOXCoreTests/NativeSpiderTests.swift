import XCTest
@testable import MacTVBOXCore

final class NativeSpiderTests: XCTestCase {
    func testExplicitRegistryAndRequirements() {
        let bili = Source(key: "b", name: "B", type: 3, api: "csp_Bili")
        XCTAssertTrue(bili.isSupported); XCTAssertEqual(bili.nativeSpider, .bili)
        XCTAssertTrue(Source(key: "d", name: "D", type: 3, api: "csp_Dm84").isSupported)
        XCTAssertFalse(Source(key: "b", name: "B", type: 1, api: "csp_Bili").isSupported)
        for (api, expected) in [("csp_Config", SourceRequirement.utility), ("csp_Douban", .utility), ("csp_Push", .utility), ("csp_Duopan", .cloud), ("csp_MiSou", .cloud), ("./drpy.js", .javascript), ("csp_Unknown", .unadapted)] {
            let source = Source(key: api, name: api, type: 3, api: api)
            XCTAssertFalse(source.isSupported); XCTAssertEqual(source.requirement, expected)
        }
        var bridged = bili; bridged.bridgeURL = "http://127.0.0.1:5757/bili"
        XCTAssertTrue(bridged.usesHTTPSpider); XCTAssertEqual(bridged.requirement, .bridge)
    }
    func testBiliSearchGroupingRespectsCredentialsBridgesAndSearchFlags() {
        let plain = Source(key: "b", name: "Bili", type: 3, api: "csp_Bili")
        var classroom = plain; classroom.key = "school"; classroom.ext = .object(["json": .string("https://metadata.example/school")])
        var loggedIn = plain; loggedIn.key = "login"; loggedIn.ext = .object(["cookie": .string("local=private")])
        var disabled = plain; disabled.key = "disabled"; disabled.searchable = false
        var bridged = plain; bridged.key = "bridge"; bridged.bridgeURL = "https://bridge.example/bili"
        let dm = Source(key: "dm", name: "DM", type: 3, api: "csp_Dm84")
        let groups = SourceSearch.groups([plain, dm, classroom, loggedIn, disabled, bridged])
        XCTAssertEqual(groups.map { $0.map(\.key) }, [["b", "school"], ["dm"], ["login"], ["bridge"]])
    }
    func testHTTPRestrictionsHaveActionableErrors() {
        XCTAssertTrue(HTTPFailure(statusCode: 412).localizedDescription.contains("拦截"))
        XCTAssertTrue(HTTPFailure(statusCode: 429).localizedDescription.contains("限流"))
        XCTAssertTrue(HTTPFailure(statusCode: 404).localizedDescription.contains("不存在"))
        XCTAssertTrue(HTTPFailure(statusCode: 503).localizedDescription.contains("503"))
    }
    func testBiliErrorCodesNeverBecomeEmptyResults() throws {
        for text in [#"{"code":-101,"message":"login"}"#, #"{"code":-412,"message":"risk"}"#, #"{"code":-404}"#, #"{"code":0}"#, #"{}"#] {
            XCTAssertThrowsError(try BiliSpiderProvider.response(Data(text.utf8)))
        }
        XCTAssertEqual(try BiliSpiderProvider.response(Data(#"{"code":0,"data":{"title":"OK"}}"#.utf8))["title"] as? String, "OK")
    }
    func testBiliCategoriesFilterUnsupportedToolsAndUPRules() throws {
        let data = Data(#"{"class":[{"type_id":"peizhi","type_name":"登录"},{"type_id":"x/{pg}","type_name":"UP"},{"type_id":"纪录片","type_name":"纪录片"},{"type_id":"纪录片","type_name":"重复"}]}"#.utf8)
        XCTAssertEqual(try BiliSpiderProvider.parseCategories(data), [Category(id: "纪录片", name: "纪录片")])
        XCTAssertThrowsError(try BiliSpiderProvider.parseCategories(Data("{}".utf8)))
    }
    func testBiliSearchAndPagination() throws {
        let page = try BiliSpiderProvider.parseList(["result": [["aid": 2, "title": "<em>公开</em>课程", "pic": "//cdn.example/cover.jpg", "author": "作者"], ["aid": 2, "title": "重复"]], "numPages": 4], key: "result", page: 2)
        XCTAssertEqual(page.videos.count, 1); XCTAssertEqual(page.videos[0].title, "公开课程")
        XCTAssertEqual(page.videos[0].poster, "https://cdn.example/cover.jpg"); XCTAssertEqual(page.pageCount, 4)
        XCTAssertTrue(try BiliSpiderProvider.parseList(["result": []], key: "result", page: 1).videos.isEmpty)
        XCTAssertThrowsError(try BiliSpiderProvider.parseList(["result": [["aid": "../escape", "title": "bad"]]], key: "result", page: 1))
    }
    func testBiliDetailAndOpaqueEpisodeIdentity() throws {
        let body: [String: Any] = ["aid": 2, "bvid": "BV1xx411c7mD", "title": "课程", "pages": [["cid": 10, "part": "第一讲"], ["cid": 20, "part": "第二讲"]]]
        let video = try BiliSpiderProvider.parseDetail(body, requestedID: "2")
        XCTAssertEqual(video.lines[0].episodes.map(\.address), ["2:10", "2:20"])
        XCTAssertEqual(video.lines[0].episodes[0].resolution?.parseType, "native-bili")
        XCTAssertThrowsError(try BiliSpiderProvider.parseDetail(body, requestedID: "3"))
        XCTAssertFalse(BiliSpiderProvider.validID("../../test")); XCTAssertFalse(BiliSpiderProvider.validID("0"))
    }
    func testBiliPlayerRequiresSingleMP4AndNoCookieLeak() throws {
        let result = try BiliSpiderProvider.parsePlayer(["format": "mp4", "durl": [["url": "https://cdn.example/movie.mp4?token=x"]]])
        XCTAssertEqual(result.url.host, "cdn.example"); XCTAssertNil(result.headers["Cookie"])
        for payload: [String: Any] in [["dash": [:]], ["durl": []], ["durl": [["url": "https://cdn.example/a.mp4"], ["url": "https://cdn.example/b.mp4"]]], ["durl": [["url": "file:///test.mp4"]]], ["format": "flv", "durl": [["url": "https://cdn.example/a.mp4"]]], ["durl": [["url": "https://cdn.example/a.html"]]]] {
            XCTAssertThrowsError(try BiliSpiderProvider.parsePlayer(payload))
        }
    }
    func testDm84CatalogDecodingDedupAndPageCount() throws {
        let item = #"<div class="item"><a href="/v/28.html" class="cover lazy" data-bg="https://cdn.example/a.jpg?a=1&amp;b=2"></a><a class="title" href="/v/28.html" title="动漫&amp;测试">动漫</a><span class="desc">第3话</span></div>"#
        let page = try Dm84SpiderProvider.parseList(item + item + #"<a href="/list-1-20.html">尾页</a>"#, page: 2)
        XCTAssertEqual(page.videos.count, 1); XCTAssertEqual(page.videos[0].id, "28"); XCTAssertEqual(page.videos[0].title, "动漫&测试")
        XCTAssertEqual(page.videos[0].poster, "https://cdn.example/a.jpg?a=1&b=2"); XCTAssertEqual(page.pageCount, 20)
        XCTAssertEqual(page.categories.count, 4)
        XCTAssertThrowsError(try Dm84SpiderProvider.parseList("<html>404</html>", page: 1))
        XCTAssertTrue(try Dm84SpiderProvider.parseList("没有找到相关内容", page: 1).videos.isEmpty)
    }
    func testDm84EpisodesSortWithinEachLineAndRejectForeignIDs() throws {
        let html = #"<h1 class="v_title"><a>测试动漫</a></h1><meta name="og:video:actor" content="演员"/><ul class="play_list current"><li><a href="/p/28-1-10.html">10</a></li><li><a href="/p/28-1-2.html">2</a></li><li><a href="/p/28-1-1.html">1</a></li><li><a href="/p/29-1-1.html">外部</a></li><li><a href="/p/28-1-2.html">重复</a></li></ul><ul class="play_list"><a href="/p/28-2-1.html">线路2</a></ul>"#
        let video = try Dm84SpiderProvider.parseDetail(html, id: "28")
        XCTAssertEqual(video.lines.count, 2); XCTAssertEqual(video.lines[0].episodes.map(\.name), ["1", "2", "10"])
        XCTAssertEqual(video.actors, "演员"); XCTAssertEqual(video.lines[0].episodes[0].resolution?.parseType, "native-dm84")
        XCTAssertThrowsError(try Dm84SpiderProvider.parseDetail(html, id: "30"))
    }
    func testDm84FrameAllowlistAndChallenges() throws {
        let frame = try Dm84SpiderProvider.playerFrame(#"<iframe src="https://ad.example"></iframe><iframe src="https://hhjx.hhplayer.com/?url=a&amp;t=1"></iframe>"#)
        XCTAssertEqual(frame.query, "url=a&t=1")
        for html in [#"<iframe src="https://hhjx.hhplayer.com.evil.example/"></iframe>"#, #"<iframe src="http://hhjx.hhplayer.com/"></iframe>"#, #"<iframe src="https://hhjx.hhplayer.com:8888/"></iframe>"#, #"<title>Just a moment</title>"#] { XCTAssertThrowsError(try Dm84SpiderProvider.playerFrame(html)) }
    }
    func testDm84BootstrapOnlyJSONAndExpectedFields() throws {
        let html = #"<script>window.__HHJX_BOOTSTRAP__={"url":"encrypted-id","t":123,"key":"ephemeral","ts_key":"not-forwarded","failure_html":"<b>error</b>"};</script>"#
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Dm84SpiderProvider.bootstrap(html)) as? [String: Any])
        XCTAssertEqual(json["client_fallback"] as? Bool, false); XCTAssertNil(json["ts_key"]); XCTAssertEqual(json.count, 4)
        for html in ["window.__HHJX_BOOTSTRAP__=eval('bad');", #"window.__HHJX_BOOTSTRAP__={"url":"x"};"#] { XCTAssertThrowsError(try Dm84SpiderProvider.bootstrap(html)) }
    }
    func testDm84PlayerRejectsSecondaryParsersAndNonMedia() throws {
        let ref = URL(string: "https://hhjx.hhplayer.com/")!
        let media = try Dm84SpiderProvider.parsePlayer(Data(#"{"code":200,"url":"https://cdn.example/video.m3u8"}"#.utf8), referer: ref)
        XCTAssertEqual(media.headers["Referer"], ref.absoluteString); XCTAssertNil(media.headers["Cookie"])
        for body in [#"{"code":500,"msg":"expired"}"#, #"{"code":200,"url":"https://example.com/watch.html"}"#, #"{"code":200,"url":"file:///video.mp4"}"#, #"{"code":200,"url":"https://cdn.example/video.mp4","ext":"youku"}"#] { XCTAssertThrowsError(try Dm84SpiderProvider.parsePlayer(Data(body.utf8), referer: ref)) }
    }
    func testInvalidEpisodeIDsFailBeforeNetwork() async throws {
        let client = TVClient()
        for api in ["csp_Bili", "csp_Dm84"] {
            do {
                _ = try await client.resolve(source: Source(key: api, name: api, type: 3, api: api), episode: Episode(name: "bad", address: "file:///tmp/test"))
                XCTFail("Invalid episode must not resolve")
            } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }
    private func fixtureClient() -> TVClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NativeSpiderFixtureProtocol.self]
        return TVClient(session: URLSession(configuration: config))
    }
    func testBiliNativeRoutingAndCookieScope() async throws {
        let source = Source(key: "b", name: "Bili", type: 3, api: "csp_Bili", ext: .object(["cookie": .string("local=test"), "json": .string("https://metadata.example/categories")]))
        let client = fixtureClient()
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.categories.map(\.id), ["课程"])
        let search = try await client.browse(source: source, query: "中文 + &")
        XCTAssertEqual(search.videos.first?.id, "2")
        let video = try await client.detail(source: source, id: "2")
        let media = try await client.resolve(source: source, episode: XCTUnwrap(video.lines.first?.episodes.first))
        XCTAssertEqual(media.url.absoluteString, "https://cdn.example/test.mp4")
        XCTAssertNil(media.headers["Cookie"])
    }
    func testBiliRemoteCookieFileRejected() async throws {
        let source = Source(key: "b", name: "Bili", type: 3, api: "csp_Bili", ext: .object(["cookie": .string("https://untrusted.example/cookie")]))
        do { _ = try await fixtureClient().browse(source: source); XCTFail("Remote cookie must not be fetched") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Cookie")) }
    }
    func testDm84NativeEndToEndPOSTAndSearchEncoding() async throws {
        let source = Source(key: "d", name: "Dm84", type: 3, api: "csp_Dm84")
        let client = fixtureClient()
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.videos.first?.id, "28")
        let search = try await client.browse(source: source, page: 2, query: "猫 + &")
        XCTAssertEqual(search.videos.count, 1)
        let video = try await client.detail(source: source, id: "28")
        let media = try await client.resolve(source: source, episode: XCTUnwrap(video.lines.first?.episodes.first))
        XCTAssertEqual(media.url.absoluteString, "https://cdn.example/test.mp4")
        XCTAssertEqual(media.headers["Referer"], "https://hhjx.hhplayer.com/")
    }
    func testExplicitBridgeOverridesNativeAdapter() async throws {
        var source = Source(key: "b", name: "Bili", type: 3, api: "csp_Bili")
        source.bridgeURL = "https://bridge.example/api"
        let home = try await fixtureClient().browse(source: source)
        XCTAssertEqual(home.videos.first?.id, "bridge-result")
    }
    func testLiveBiliProtocol() async throws {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_SPIDER"] == "1" else { throw XCTSkip("Opt in with MACTVBOX_LIVE_SPIDER=1") }
        let source = Source(key: "b", name: "Bili", type: 3, api: "csp_Bili")
        let client = TVClient()
        let home = try await client.browse(source: source)
        XCTAssertFalse(home.videos.isEmpty)
        let search = try await client.browse(source: source, query: "语文")
        XCTAssertFalse(search.videos.isEmpty)
        let video = try await client.detail(source: source, id: "BV1xx411c7mD")
        let media = try await client.resolve(source: source, episode: XCTUnwrap(video.lines.first?.episodes.first))
        XCTAssertEqual(media.url.pathExtension, "mp4")
        print("Live Bili: home/search/detail/MP4 resolution passed; playback not asserted")
    }
    func testLiveDm84Protocol() async throws {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_SPIDER"] == "1" else { throw XCTSkip("Opt in with MACTVBOX_LIVE_SPIDER=1") }
        let source = Source(key: "d", name: "Dm84", type: 3, api: "csp_Dm84")
        let client = TVClient()
        let home = try await client.browse(source: source)
        XCTAssertFalse(home.videos.isEmpty)
        let search = try await client.browse(source: source, query: "猫")
        XCTAssertFalse(search.videos.isEmpty)
        let category = try await client.browse(source: source, category: "1", page: 2)
        XCTAssertFalse(category.videos.isEmpty)
        let video = try await client.detail(source: source, id: "28")
        let media = try await client.resolve(source: source, episode: XCTUnwrap(video.lines.first?.episodes.first))
        XCTAssertTrue(["mp4", "m3u8"].contains(media.url.pathExtension))
        print("Live Dm84: home/search/category/detail/media resolution passed; playback not asserted")
    }
}

/// Intercepts fixed production origins; no live requests in deterministic tests.
private final class NativeSpiderFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let url = request.url!
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
            var body = "", status = 200
            if url.host == "api.bilibili.com" {
                guard request.value(forHTTPHeaderField: "Cookie") == "local=test", request.value(forHTTPHeaderField: "Referer") == "https://www.bilibili.com/" else { throw TVError.message("Bili request headers mismatch") }
                switch url.path {
                case "/x/web-interface/popular": body = #"{"code":0,"data":{"list":[{"aid":2,"title":"课程"}]}}"#
                case "/x/web-interface/search/type":
                    guard value("keyword") == "中文 + &", value("search_type") == "video" else { throw TVError.message("Bili keyword encoding mismatch") }
                    body = #"{"code":0,"data":{"result":[{"aid":2,"title":"课程"}],"numPages":1}}"#
                case "/x/web-interface/view":
                    guard value("aid") == "2" else { throw TVError.message("Bili ID mismatch") }
                    body = #"{"code":0,"data":{"aid":2,"title":"课程","pages":[{"cid":10,"part":"1"}]}}"#
                case "/x/player/playurl":
                    guard value("avid") == "2", value("cid") == "10", value("fnval") == "1" else { throw TVError.message("Bili playback parameters mismatch") }
                    body = #"{"code":0,"data":{"durl":[{"url":"https://cdn.example/test.mp4"}]}}"#
                default: status = 404
                }
            } else if url.host == "metadata.example" {
                guard request.value(forHTTPHeaderField: "Cookie") == nil else { throw TVError.message("API cookie leaked to metadata host") }
                body = #"{"class":[{"type_id":"课程","type_name":"课程"}]}"#
            } else if url.host == "dm84.net" {
                if url.path == "/v/28.html" {
                    body = #"<h1>动漫</h1><ul class="play_list"><a href="/p/28-1-1.html">1</a></ul>"#
                } else if url.path == "/p/28-1-1.html" {
                    body = #"<iframe src="https://hhjx.hhplayer.com/?url=opaque"></iframe>"#
                } else {
                    if url.path != "" && url.path != "/" && url.path != "/s-猫 + &---------2.html" { throw TVError.message("Dm84 search route mismatch: " + url.path) }
                    body = #"<div class="item"><a class="title" href="/v/28.html" title="动漫">动漫</a></div>"#
                }
            } else if url.host == "hhjx.hhplayer.com" {
                if url.path == "/api/parse" {
                    guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Content-Type") == "application/json", request.value(forHTTPHeaderField: "Referer") == "https://hhjx.hhplayer.com/?url=opaque" else { throw TVError.message("Dm84 POST headers mismatch") }
                    var data = request.httpBody ?? Data()
                    if data.isEmpty, let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        var buffer = [UInt8](repeating: 0, count: 4096)
                        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
                    }
                    let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard payload?["key"] as? String == "test", payload?["client_fallback"] as? Bool == false else { throw TVError.message("Dm84 POST payload mismatch") }
                    body = #"{"code":200,"url":"https://cdn.example/test.mp4"}"#
                } else { body = #"window.__HHJX_BOOTSTRAP__={"url":"opaque","key":"test","t":123};"# }
            } else if url.host == "bridge.example" { body = #"{"list":[{"vod_id":"bridge-result","vod_name":"Bridge"}]}"# }
            else { throw TVError.message("Unexpected fixture host") }
            let data = Data(body.utf8)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(data.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
