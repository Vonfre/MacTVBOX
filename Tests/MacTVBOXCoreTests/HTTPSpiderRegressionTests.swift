import XCTest
@testable import MacTVBOXCore

final class HTTPSpiderRegressionTests: XCTestCase {
    func testBridgeExecutionFailuresAreNotEmptySuccessfulPages() {
        let data = Data(#"{"bridge_error":"Android 插件执行失败（ClassNotFoundException）"}"#.utf8)
        do {
            _ = try HTTPSpiderProvider.parsePage(data, baseURL: URL(string: "http://127.0.0.1:19978/api")!)
            XCTFail("Expected bridge failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("ClassNotFoundException")) }
        do {
            _ = try HTTPSpiderProvider.parsePlayer(data)
            XCTFail("Expected bridge failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("ClassNotFoundException")) }
    }
    func testEmptyAndSecondaryPlayerResponsesAreNotReportedAsPlayable() {
        do {
            _ = try HTTPSpiderProvider.parsePlayer(Data(#"{"parse":0,"url":""}"#.utf8))
            XCTFail("Expected empty address failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("空播放地址")) }
        XCTAssertThrowsError(try HTTPSpiderProvider.parsePlayer(Data(#"{"parse":0,"url":"https://a.test/video.m3u8","playUrl":"https://parser.test/?url="}"#.utf8)))
        XCTAssertThrowsError(try HTTPSpiderProvider.parsePlayer(Data(#"{"parse":1,"jx":1,"url":"https://www.iqiyi.com/video.html"}"#.utf8)))
    }
    func testDefaultLineAvoidsRestrictionLabelsWithoutReorderingFlags() {
        let episode = Episode(name: "1", address: "opaque-id")
        let video = Video(id: "v", title: "v", lines: [PlayLine(name: "VIP", episodes: [episode]), PlayLine(name: "empty", episodes: []), PlayLine(name: "normal", episodes: [episode])])
        XCTAssertEqual(video.preferredLineIndex, 2)
        XCTAssertEqual(video.lines[0].name, "VIP")
        XCTAssertEqual(Video(id: "v", title: "v").preferredLineIndex, 0)
        XCTAssertEqual(Video(id: "v", title: "v", lines: [video.lines[0]]).preferredLineIndex, 0)
    }
    func testExternalServiceMediaHeadersArePreservedForMacPlayback() throws {
        let data = Data(#"{"parse":0,"jx":0,"url":"https://media.test/video.m3u8","header":"{\"User-Agent\":\"AndroidPlayer/1\",\"Referer\":\"https://site.test/\",\"x-requested-with\":\"com.jp3.xg3\"}"}"#.utf8)
        let media = try HTTPSpiderProvider.parsePlayer(data)
        XCTAssertEqual(media.headers["x-requested-with"], "com.jp3.xg3")
        XCTAssertEqual(media.headers["Referer"], "https://site.test/")
        XCTAssertEqual(media.url.pathExtension, "m3u8")
    }
}
