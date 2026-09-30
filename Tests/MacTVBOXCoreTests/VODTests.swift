import XCTest
@testable import MacTVBOXCore

final class VODTests: XCTestCase {
    func testJSONMixedNumbersAndRelativePoster() throws {
        let json = #"{"page":"2","pagecount":5,"class":[{"type_id":1,"type_name":"电影"}],"list":[{"vod_id":9,"vod_name":"测试 &amp; 影片","vod_pic":"/poster.jpg","vod_content":"<p>测试</p>&nbsp;说明","vod_year":2026,"vod_play_from":"HLS$$$MP4","vod_play_url":"第一集$https://example.com/1.m3u8#第二集$https://example.com/2.m3u8$$$正片$https://example.com/movie.mp4"}]}"#
        let page = try VODParser.parse(Data(json.utf8), baseURL: URL(string: "https://example.com/api/"))
        XCTAssertEqual(page.page, 2); XCTAssertEqual(page.pageCount, 5)
        XCTAssertEqual(page.categories.first?.id, "1")
        let video = try XCTUnwrap(page.videos.first)
        XCTAssertEqual(video.title, "测试 & 影片"); XCTAssertEqual(video.poster, "https://example.com/poster.jpg")
        XCTAssertEqual(video.year, "2026"); XCTAssertEqual(video.summary, "测试 说明")
        XCTAssertEqual(video.lines.count, 2); XCTAssertEqual(video.lines[0].episodes.count, 2)
    }
    func testXMLAndCDATA() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?><rss><class><ty id="1">电影</ty></class><list page="1" pagecount="3"><video><id>12</id><name><![CDATA[测试影片]]></name><pic>//example.com/poster.jpg</pic><type>电影</type><year>2026</year><des><![CDATA[<p>剧情介绍</p>]]></des><dl><dd flag="hls"><![CDATA[正片$https://example.com/movie.m3u8]]></dd><dd flag="mp4">正片$https://example.com/movie.mp4</dd></dl></video></list></rss>
        """
        let page = try VODParser.parse(Data(xml.utf8), baseURL: URL(string: "https://example.com/api"))
        XCTAssertEqual(page.pageCount, 3); XCTAssertEqual(page.categories.count, 1)
        XCTAssertEqual(page.videos.first?.id, "12"); XCTAssertEqual(page.videos.first?.summary, "剧情介绍")
        XCTAssertEqual(page.videos.first?.poster, "https://example.com/poster.jpg")
        XCTAssertEqual(page.videos.first?.lines.count, 2)
    }
    func testXMLRejectsEntitiesAndHTML() {
        let inputs = ["<!DOCTYPE rss [<!ENTITY x 'bomb'>]><rss><list/></rss>", "<html><body>Oops</body></html>", "<rss><list>"]
        for input in inputs { XCTAssertThrowsError(try VODParser.parse(Data(input.utf8))) }
    }
    func testEmptyResponseAndInvalidStructure() throws {
        XCTAssertTrue(try VODParser.parse(Data(#"{"list":[]}"#.utf8)).videos.isEmpty)
        XCTAssertThrowsError(try VODParser.parse(Data(#"{"data":[]}"#.utf8)))
    }
    func testDeduplicateVideoAndCategoryIDs() throws {
        let json = #"{"class":[{"type_id":1,"type_name":"一"},{"type_id":1,"type_name":"一"}],"list":[{"vod_id":1,"vod_name":"一"},{"vod_id":1,"vod_name":"重复"},{"vod_id":2}]}"#
        let page = try VODParser.parse(Data(json.utf8))
        XCTAssertEqual(page.videos.count, 1); XCTAssertEqual(page.categories.count, 1)
    }
    func testDollarInSignedURLPreserved() {
        let lines = VODParser.parseLines(from: "hls", urls: "正片$https://example.com/movie.m3u8?token=a$b$c")
        XCTAssertEqual(lines[0].episodes[0].address, "https://example.com/movie.m3u8?token=a$b$c")
    }
    func testMissingLineNamesAndBareURLs() {
        let lines = VODParser.parseLines(from: "", urls: "https://example.com/a.mp4$$$https://example.com/b.mp4")
        XCTAssertEqual(lines.count, 2); XCTAssertNotEqual(lines[0].id, lines[1].id)
        XCTAssertEqual(lines[0].episodes[0].name, "第 1 集")
    }
    func testOpaquePluginURLsNotDirectlyPlayable() {
        XCTAssertNil(Episode(name: "测试", address: "magnet:?xt=urn:btih:test").directURL)
        XCTAssertNil(Episode(name: "测试", address: "cloud-token").directURL)
        XCTAssertNil(Episode(name: "测试", address: "javascript:alert(1)").directURL)
    }
    func testSaveRestoreRoundTrip() throws {
        let saved = SavedVideo(video: Video(id: "v", title: "影片"), source: Source(key: "s", name: "源", type: 1, api: "https://example.com"), episode: Episode(name: "一", address: "https://example.com/a.mp4"), position: 123.5)
        let restored = try JSONDecoder().decode(SavedVideo.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored, saved)
    }
}
