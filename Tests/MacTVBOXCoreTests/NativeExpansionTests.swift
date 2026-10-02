import XCTest
@testable import MacTVBOXCore

final class NativeExpansionTests: XCTestCase {
    private func provider(_ kind: NativeSpider) -> PublicWebSpiderProvider {
        PublicWebSpiderProvider(client: TVClient(), source: Source(key: "test", name: "test", type: 3, api: kind.rawValue))
    }
    func testRegistryAndExactJSReplacement() {
        for api in ["csp_FirstAid", "csp_YGP", "csp_Kanqiu", "csp_Kugou", "csp_AppQi", "csp_AppRJ", "csp_Jpys"] {
            let source = Source(key: api, name: api, type: 3, api: api)
            XCTAssertTrue(source.isSupported); XCTAssertEqual(source.requirement, .native)
        }
        var source = Source(key: "kids", name: "kids", type: 3, api: "http://xn--z7x900a.net/api/drpy2.min.js", ext: .string("./js/兔小贝.js"))
        XCTAssertEqual(source.nativeSpider, .tuxiaobei)
        source.ext = .string("./js/other.js"); XCTAssertNil(source.nativeSpider)
        source.ext = .string("./js/兔小贝.js"); source.api = "https://other.test/drpy2.min.js"
        XCTAssertNil(source.nativeSpider); XCTAssertFalse(source.isSupported)
    }
    func testSpecialtyTitlesNeverMergeIntoFeatureFilmSources() {
        let video = Video(id: "1", title: "同名", year: "2026")
        let hits = ["csp_Jianpian", "csp_Gz360", "csp_YGP", "csp_Kugou", "csp_Kanqiu", "csp_FirstAid", "native_TuXiaoBei"].map {
            SourceMatch(video: video, source: Source(key: $0, name: $0, type: 3, api: $0))
        }
        let groups = TitleMatcher.groups(hits)
        XCTAssertEqual(groups.count, 6)
        XCTAssertEqual(groups.first(where: { $0.matches.first?.source.contentRole == .video })?.sourceCount, 2)
    }
    func testFirstAidAllEightSectionsAndDeduplication() throws {
        let p = provider(.firstAid)
        let html = (0..<8).map { i in
            "<div class='jj-title-li'><a href='/jijiu/article/A\(i).html' title='栏目\(i)'><img src='/\(i).jpg'></a></div><div><img class='block100'></div>"
        }.joined() + "</body>"
        XCTAssertEqual(try p.parseList(html, category: nil, page: 1).videos.count, 8)
        for i in 0..<8 {
            let page = try p.parseList(html, category: "jijiu|\(i)", page: 1)
            XCTAssertEqual(page.videos.map(\.title), ["栏目\(i)"])
        }
        XCTAssertThrowsError(try p.parseList(html, category: "jijiu|9", page: 1))
        XCTAssertThrowsError(try p.parseList("<html>404</html>", category: nil, page: 1))
    }
    func testTrailersHaveExplicitContentRoleAndOnlyPublicEpisodes() throws {
        let p = provider(.trailers)
        let html = "<h1>测试预告</h1><a class='tlist-bbs-tdtitle' href='/show/12'>预告1</a><a class='tlist-bbs-tdtitle' href='/show/12'>重复</a><a href='https://other.test/play'>广告</a>"
        let video = try p.parseDetail(html, id: "/movie/12")
        XCTAssertEqual(video.lines[0].episodes.count, 1)
        XCTAssertEqual(video.remarks, "预告片 · 非正片")
        XCTAssertEqual(video.lines[0].episodes[0].address, "https://www.6huo.com/show/12")
        XCTAssertThrowsError(try p.parseDetail("<h1>没有预告</h1>", id: "/movie/12"))
    }
    func testLiteralMediaOnlyAndJSONEscapes() throws {
        XCTAssertEqual(PublicWebSpiderProvider.mediaAddress(#"{"contentUrl":"https:\/\/cdn.test\/v.mp4"}"#), "https://cdn.test/v.mp4")
        XCTAssertEqual(PublicWebSpiderProvider.mediaAddress("<video src='https://cdn.test/v.mp4?a=1&amp;b=2'>"), "https://cdn.test/v.mp4?a=1&b=2")
        for html in ["<iframe src='https://cdn.test/v.mp4'>", "video: eval('x')", "video: 'file:///x.mp4'", "video: 'https://cdn.test/watch.html'"] {
            XCTAssertNil(PublicWebSpiderProvider.mediaAddress(html))
        }
    }
    func testSportsLockedLinksAndRestrictedEventsRejected() throws {
        let p = provider(.kanqiu)
        func envelope(_ object: [String: Any]) throws -> Data {
            let encoded = try JSONSerialization.data(withJSONObject: object).base64EncodedString()
            return try JSONSerialization.data(withJSONObject: ["data": "prefix" + encoded + "xx"])
        }
        let links: [[String: Any]] = [
            ["name": "公开", "url": "https://cdn.test/live.m3u8", "shareLock": 0],
            ["name": "加锁", "url": "https://cdn.test/private.m3u8", "shareLock": 1],
            ["name": "广告", "url": "https://unknown.test/?url=https://cdn.test/live.m3u8"]]
        let detail = try p.parseSportsDetail(envelope(["shareStatusCheck": 0, "links": links]), id: "123")
        XCTAssertEqual(detail.lines.map(\.name), ["公开"])
        XCTAssertThrowsError(try p.parseSportsDetail(envelope(["shareStatusCheck": 1, "links": links]), id: "123"))
        XCTAssertNil(PublicWebSpiderProvider.sportsMedia("https://play.88player.top.evil.test/m3u8.html?url=https://cdn.test/a.m3u8"))
        XCTAssertEqual(PublicWebSpiderProvider.sportsMedia("https://play.88player.top/m3u8.html?url=https%3A%2F%2Fcdn.test%2Fa.m3u8")?.host, "cdn.test")
        XCTAssertThrowsError(try p.parseSportsDetail(Data("{}".utf8), id: "123"))
        XCTAssertThrowsError(try p.parseSportsDetail(envelope(["links": links]), id: "123"))
        XCTAssertThrowsError(try p.parseSportsDetail(envelope(["shareStatusCheck": 0, "links": [["url": "https://cdn.test/a.m3u8"]]]), id: "123"))
    }
    func testPublicResolverRejectsStaleAndForeignEpisodeContext() async throws {
        let p = provider(.trailers)
        for episode in [p.episode("bad", "https://other.test/show/12"), p.episode("bad", "https://www.6huo.com:8080/show/12"), provider(.firstAid).episode("wrong source", "https://cdn.test/a.mp4")] {
            do { _ = try await p.resolve(episode); XCTFail("Unexpected media resolution") } catch {}
        }
        let result = try await p.resolve(p.episode("ok", "https://cdn.test/a.mp4"))
        XCTAssertEqual(result.url.host, "cdn.test"); XCTAssertNil(result.headers["Cookie"])
    }
    func testKugouIDsAndMVMetadata() throws {
        let hash = String(repeating: "a", count: 32), mv = String(repeating: "b", count: 32)
        let song = try XCTUnwrap(KugouSpiderProvider.song(["hash": hash, "mvhash": mv, "filename": "公开 MV"]))
        XCTAssertEqual(song.lines.count, 2); XCTAssertEqual(song.lines[1].episodes[0].address, "mv:" + mv)
        XCTAssertTrue(song.remarks.contains("非影视正片"))
        XCTAssertNil(KugouSpiderProvider.song(["hash": "../../test", "filename": "bad"]))
        XCTAssertFalse(KugouSpiderProvider.hash(hash + "?token=x"))
    }
    func testAppQiEncryptedEnvelopeAndAuthorizationErrors() throws {
        let key = Data("0123456789abcdef".utf8)
        let encrypted = try AppGetProvider.aes(Data(#"{"recommend_list":[]}"#.utf8), key: key, iv: key, encrypt: true)
        let bytes = try JSONSerialization.data(withJSONObject: ["data": encrypted.base64EncodedString()])
        XCTAssertTrue(try LegacyAppSpiderProvider.decode(bytes, key: key)["recommend_list"] != nil)
        for body in [#"{"code":403,"data":""}"#, #"{"data":"broken"}"#, "{}", "<html>verify</html>"] {
            XCTAssertThrowsError(try LegacyAppSpiderProvider.decode(Data(body.utf8), key: key))
        }
        XCTAssertThrowsError(try LegacyAppSpiderProvider.decode(bytes, key: Data("short".utf8)))
    }
    func testLegacyDetailHeadersContextsAndEmptyLines() throws {
        let rj: [String: Any] = ["vod_id": 12, "vod_name": "示例", "vod_play_list": [["name": "高清", "ua": "fixture", "referer": "https://ref.test/", "parse_urls": ["https://parse.test/?url="], "urls": [["name": "01", "url": "opaque"]]]]]
        let detail = try LegacyAppSpiderProvider.detail(rj, id: "12", qi: false)
        let episode = detail.lines[0].episodes[0]
        XCTAssertEqual(episode.resolution?.parseType, "native-apprj")
        XCTAssertEqual(episode.resolution?.headers["User-Agent"], "fixture")
        XCTAssertThrowsError(try LegacyAppSpiderProvider.detail(rj, id: "13", qi: false))
        XCTAssertThrowsError(try LegacyAppSpiderProvider.detail(["vod_id": 12, "vod_name": "示例", "vod_play_list": []], id: "12", qi: false))
        let qi: [String: Any] = ["vod": ["vod_id": 12, "vod_name": "示例"], "vod_play_list": [["player_info": ["show": "高清", "parse": "https://parse.test/"], "urls": [["name": "01", "url": "opaque", "token": "fixture-only", "parse_api_url": "https://cdn.test/a.mp4"]]]]]
        let qiDetail = try LegacyAppSpiderProvider.detail(qi, id: "12", qi: true)
        XCTAssertEqual(qiDetail.lines[0].name, "高清")
        XCTAssertEqual(qiDetail.lines[0].episodes[0].resolution?.parseType, "native-appqi")
    }
    func testLegacyMediaRejectsHTMLAndUnsafeAddresses() throws {
        XCTAssertEqual(try LegacyAppSpiderProvider.media(["data": ["url": "https://cdn.test/a.m3u8", "UA": "safe"]], headers: [:]).headers["User-Agent"], "safe")
        XCTAssertNil(try LegacyAppSpiderProvider.media(["url": "https://cdn.test/a.mp4", "UA": "x\r\nCookie: secret"], headers: [:]).headers["User-Agent"])
        for address in ["file:///a.mp4", "https://cdn.test/login", "", "javascript:alert(1)"] {
            XCTAssertThrowsError(try LegacyAppSpiderProvider.media(["url": address], headers: [:]))
        }
        let body = String(data: LegacyAppSpiderProvider.multipart(["keyword": "片名+&", "page": "1"], boundary: "fixture"), encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"keyword\"\r\n\r\n片名+&\r\n")); XCTAssertTrue(body.hasSuffix("--fixture--\r\n"))
    }
}
