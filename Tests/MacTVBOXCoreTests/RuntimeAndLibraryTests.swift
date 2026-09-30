import XCTest
@testable import MacTVBOXCore

final class RuntimeAndLibraryTests: XCTestCase {
    func testHTTPSpiderCapabilityAndOldSnapshots() throws {
        let old = Data(#"{"key":"a","name":"旧源","type":3,"api":"csp_Test","searchable":true}"#.utf8)
        var source = try JSONDecoder().decode(Source.self, from: old)
        XCTAssertFalse(source.isSupported)
        XCTAssertNil(source.bridgeURL)
        source.bridgeURL = "http://127.0.0.1:5757/api/test"
        XCTAssertTrue(source.isSupported)
        XCTAssertTrue(source.usesHTTPSpider)
        XCTAssertEqual(try JSONDecoder().decode(Source.self, from: JSONEncoder().encode(source)), source)
        XCTAssertTrue(Source(key: "t", name: "T", type: 4, api: "https://example.com/api/demo").isSupported)
        XCTAssertFalse(Source(key: "t", name: "T", type: 4, api: "file:///plugin").isSupported)
    }
    func testRemoteConfigurationCannotEnableBridge() throws {
        let data = Data(#"{"sites":[{"key":"x","type":3,"api":"csp_Test","bridgeURL":"https://untrusted.example/run"}]}"#.utf8)
        let source = try XCTUnwrap(ConfigurationParser.parse(data).sources.first)
        XCTAssertNil(source.bridgeURL)
        XCTAssertFalse(source.isSupported)
    }
    func testHTTPSpiderPreservesOpaqueIDsAndExactDuplicateFlags() throws {
        let data = Data(#"{"list":[{"vod_id":"v","vod_name":"V","vod_pic":"/cover.jpg","vod_play_from":"unused$$$线路 · 1$$$线路 · 1","vod_play_url":"$$$第一集$/opaque?x=1&y=2#第二集$id+中$$$第三集$./relative"}]}"#.utf8)
        let page = try HTTPSpiderProvider.parsePage(data, baseURL: URL(string: "https://example.com/api/test")!)
        let video = try XCTUnwrap(page.videos.first)
        XCTAssertEqual(video.poster, "https://example.com/cover.jpg")
        XCTAssertEqual(video.lines.count, 2)
        XCTAssertEqual(video.lines[0].episodes[0].address, "/opaque?x=1&y=2")
        XCTAssertEqual(video.lines[0].episodes[1].address, "id+中")
        XCTAssertEqual(video.lines[1].episodes[0].address, "./relative")
        XCTAssertEqual(video.lines[0].episodes[0].resolution?.parser, "线路 · 1")
        XCTAssertEqual(video.lines[1].episodes[0].resolution?.parser, "线路 · 1")
    }
    func testHTTPSpiderHomeOnlyClassesAndErrors() throws {
        let url = URL(string: "http://127.0.0.1/api/test")!
        let page = try HTTPSpiderProvider.parsePage(Data(#"{"class":[{"type_id":"1","type_name":"电影"}]}"#.utf8), baseURL: url)
        XCTAssertEqual(page.categories.count, 1)
        XCTAssertTrue(page.videos.isEmpty)
        XCTAssertThrowsError(try HTTPSpiderProvider.parsePage(Data(#"{"error":"unauthorized"}"#.utf8), baseURL: url))
    }
    func testHTTPSpiderPlayerHeadersAndRejection() throws {
        let media = try HTTPSpiderProvider.parsePlayer(Data(#"{"parse":0,"url":"https://media.example/video.m3u8","header":{"Referer":"https://example.com/","User-Agent":"Example"}}"#.utf8))
        XCTAssertEqual(media.headers["Referer"], "https://example.com/")
        let encoded = try HTTPSpiderProvider.parsePlayer(Data(#"{"parse":"0","jx":"0","url":"http://localhost/video","header":"{\"Referer\":\"https://example.com/\"}"}"#.utf8))
        XCTAssertEqual(encoded.headers.count, 1)
        for body in [
            #"{"parse":1,"url":"https://example.com/watch"}"#,
            #"{"parse":0,"jx":1,"url":"https://example.com/watch"}"#,
            #"{"url":"https://example.com/watch"}"#,
            #"{"parse":0,"url":"file:///etc/passwd"}"#,
            #"{"parse":0,"url":"https://example.com/watch.html"}"#,
            #"{"parse":0,"url":"https://example.com/v","header":{"Host":"bad"}}"#,
            #"{"parse":0,"url":"https://example.com/v","header":{"Referer":"a\r\nb"}}"#,
            #"{"parse":0,"url":"https://example.com/v","header":4}"#
        ] { XCTAssertThrowsError(try HTTPSpiderProvider.parsePlayer(Data(body.utf8))) }
    }
    func testHTTPSpiderRequestClearsActionsButPreservesModuleOptions() throws {
        let url = try URLTools.apiURL("http://localhost/api/demo?token=kept&extend=module&play=stale&flag=old&wd=old&ac=detail&ids=x&action=bad&refresh=1", parameters: ["play":"/opaque?x=1&b=中文+", "flag":"线路 · 1"])
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "play" }?.value, "/opaque?x=1&b=中文+")
        XCTAssertEqual(items.first { $0.name == "flag" }?.value, "线路 · 1")
        XCTAssertEqual(items.first { $0.name == "extend" }?.value, "module")
        XCTAssertEqual(items.count, 4)
    }
    func testHTTPSpiderEndToEndAndMappedSource() async throws {
        guard let base = ProcessInfo.processInfo.environment["MACTVBOX_TEST_SERVER"] else { throw XCTSkip("Start fixture server") }
        var source = Source(key: "js", name: "JS", type: 3, api: "./rule.js", ext: .string("private-not-sent"))
        source.bridgeURL = base + "/spider?token=test&extend=fixture"
        let client = TVClient()
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.categories.count, 1)
        let category = try await client.browse(source: source, category: "cat", page: 2)
        XCTAssertEqual(category.page, 2)
        let page = try await client.browse(source: source, query: "片名 + & 中文")
        XCTAssertEqual(page.videos.count, 1)
        let video = try await client.detail(source: source, id: "v1")
        let episode = try XCTUnwrap(video.lines.first?.episodes.first)
        let media = try await client.resolve(source: source, episode: episode)
        XCTAssertEqual(media.url.absoluteString, base + "/media.mp4")
        XCTAssertEqual(media.headers["Referer"], base)
        let type4 = Source(key: "4", name: "HTTP", type: 4, api: source.bridgeURL!)
        let type4Home = try await client.browse(source: type4)
        XCTAssertEqual(type4Home.categories.count, 1)
    }
    func testBatchDeletionSuppressesPeriodicUpdatesUntilExplicitPlay() {
        let source = Source(key: "s", name: "S", type: 1, api: "https://example.com")
        let a = SavedVideo(video: Video(id: "a", title: "A"), source: source)
        let b = SavedVideo(video: Video(id: "b", title: "B"), source: source)
        var guardState = HistoryDeletionGuard()
        let remaining = guardState.delete([a.id, "stale-id"], from: [a, b])
        XCTAssertEqual(remaining.map(\.id), [b.id])
        XCTAssertFalse(guardState.allowsRecording(id: a.id))
        XCTAssertTrue(guardState.allowsRecording(id: b.id))
        guardState.beginPlayback(id: a.id)
        XCTAssertTrue(guardState.allowsRecording(id: a.id))
        XCTAssertTrue(guardState.delete([a.id, b.id], from: [a, b]).isEmpty)
    }
    func testProgressFormattingIsFiniteAndIncludesHours() {
        var item = SavedVideo(video: Video(id: "a", title: "A"), source: Source(key: "s", name: "S", type: 1, api: "https://example.com"))
        item.position = 3671; XCTAssertEqual(item.progressText, "1:01:11")
        item.position = 61; XCTAssertEqual(item.progressText, "1:01")
        item.position = -.infinity; XCTAssertEqual(item.progressText, "0:00")
        item.position = .nan; XCTAssertEqual(item.progressText, "0:00")
        item.position = -4; XCTAssertEqual(item.progressText, "0:00")
    }
}
