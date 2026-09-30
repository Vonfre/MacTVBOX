import XCTest
@testable import MacTVBOXCore

final class AppGetTests: XCTestCase {
    func fixtureSource(_ path: String = "") throws -> Source {
        guard let base = ProcessInfo.processInfo.environment["MACTVBOX_TEST_SERVER"] else { throw XCTSkip("Set MACTVBOX_TEST_SERVER.") }
        return Source(key: "appget", name: "fixture", type: 3, api: "csp_AppGet", ext: .string(base + path + "|0123456789abcdef"))
    }
    func testExtRoundTripAndOldSnapshotMigration() throws {
        let data = Data(#"{"sites":[{"key":"ag","name":"test","type":3,"api":"csp_AppGet","ext":"https://example.com|0123456789abcdef","jar":"plugin.jar"}]}"#.utf8)
        let config = try ConfigurationParser.parse(data)
        let source = try JSONDecoder().decode(Source.self, from: JSONEncoder().encode(config.sources[0]))
        XCTAssertTrue(source.isSupported)
        XCTAssertEqual(source.ext?.string, "https://example.com|0123456789abcdef")
        XCTAssertEqual(source.jar, "plugin.jar")
        let old = try JSONDecoder().decode(Source.self, from: Data(#"{"key":"a","name":"old","type":3,"api":"csp_AppGet","searchable":true}"#.utf8))
        XCTAssertNil(old.ext); XCTAssertFalse(old.isSupported)
    }
    func testStructuredExtensionPreserved() throws {
        let data = Data(#"{"sites":[{"key":"a","type":3,"api":"csp_Other","ext":{"nested":[1,true,null,"abc"]}}]}"#.utf8)
        let source = try ConfigurationParser.parse(data).sources[0]
        let restored = try JSONDecoder().decode(Source.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(restored.ext, source.ext)
        XCTAssertFalse(restored.isSupported)
    }
    func testAESRoundTripAndInvalidKey() throws {
        let key = Data("0123456789abcdef".utf8), plain = Data("中文 protocol test".utf8)
        let encrypted = try AppGetProvider.aes(plain, key: key, iv: key, encrypt: true)
        XCTAssertNotEqual(encrypted, plain)
        XCTAssertEqual(try AppGetProvider.aes(encrypted, key: key, iv: key, encrypt: false), plain)
        XCTAssertThrowsError(try AppGetProvider.aes(plain, key: Data("bad".utf8), iv: key, encrypt: true))
        XCTAssertThrowsError(try AppGetProvider.aes(Data([1,2,3]), key: key, iv: key, encrypt: false))
    }
    func testDirectMediaDetection() {
        XCTAssertTrue(AppGetProvider.isDirect("https://example.com/a.m3u8?token=x"))
        XCTAssertFalse(AppGetProvider.isDirect("https://example.com/watch?url=a.m3u8"))
        XCTAssertFalse(AppGetProvider.isDirect("file:///tmp/video.mp4"))
    }
    func testVerificationFlags() {
        for flag: Any in [true, 1, "1", "true"] { XCTAssertTrue(AppGetProvider.requiresVerification(["system_search_verify_status": flag])) }
        for flag: Any in [false, 0, "0", "false"] { XCTAssertFalse(AppGetProvider.requiresVerification(["system_search_verify_status": flag])) }
    }
    func testHomeCategoriesSearchAndHostResolver() async throws {
        let source = try fixtureSource("/appget-host.txt"), client = TVClient()
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.recommendations.map(\.title), ["热门电影", "热播剧集", "热播综艺"])
        XCTAssertEqual(home.categories.count, 3)
        let category = try await client.browse(source: source, category: "1", page: 2)
        XCTAssertEqual(category.page, 2); XCTAssertEqual(category.videos.count, 1)
        let search = try await client.browse(source: source, query: "片名 + & 中文")
        XCTAssertEqual(search.videos.first?.title, "原生测试影片")
    }
    func testCaptchaIsNotBypassed() async throws {
        do {
            _ = try await TVClient().browse(source: fixtureSource("/captcha"), query: "片名")
            XCTFail("Search requiring verification must stop.")
        } catch let error as TVError { XCTAssertTrue(error.localizedDescription.contains("验证码")) }
    }
    func testDetailsAndThreeResolutionPaths() async throws {
        let client = TVClient(), source = try fixtureSource()
        let video = try await client.detail(source: source, id: "ag1")
        XCTAssertEqual(video.lines.count, 3)
        for line in video.lines {
            let episode = try XCTUnwrap(line.episodes.first)
            let media = try await client.resolve(source: source, episode: episode)
            XCTAssertEqual(media.url.path, "/media.mp4")
            if line.name == "AppGet解析" { XCTAssertTrue(media.headers["Referer"] != nil) }
        }
    }
    func testLiveAppGetBrowseSearchDetailResolve() async throws {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_APPGET"] == "1", let path = ProcessInfo.processInfo.environment["MACTVBOX_CONFIG_FIXTURE"] else { throw XCTSkip("Opt-in live provider validation.") }
        let config = try ConfigurationParser.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        let source = try XCTUnwrap(config.sources.first { $0.key == "一碗" })
        let client = TVClient()
        let home = try await client.browse(source: source)
        XCTAssertTrue(home.recommendations.count > 2)
        let brief = try XCTUnwrap(home.recommendations.first?.videos.first)
        let video = try await client.detail(source: source, id: brief.id)
        let episode = try XCTUnwrap(video.lines.first?.episodes.first)
        let media = try await client.resolve(source: source, episode: episode)
        let (playlist, _) = try await client.fetch(media.url)
        XCTAssertTrue(String(data: playlist, encoding: .utf8)?.hasPrefix("#EXTM3U") == true)
        let search = try await client.browse(source: source, query: "阿嬷")
        XCTAssertFalse(search.videos.isEmpty)
        print("LIVE \(source.name): sections=\(home.recommendations.count), search=\(search.videos.count), resolved HLS for \(video.title)")
    }
}
