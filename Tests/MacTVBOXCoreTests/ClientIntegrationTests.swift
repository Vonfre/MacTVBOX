import XCTest
@testable import MacTVBOXCore

final class ClientIntegrationTests: XCTestCase {
    func base() throws -> String {
        guard let value = ProcessInfo.processInfo.environment["MACTVBOX_TEST_SERVER"] else { throw XCTSkip("Run scripts/fixture-server.py and set MACTVBOX_TEST_SERVER.") }
        return value
    }
    func testConfigurationAndRedirect() async throws {
        let client = TVClient()
        let config = try await client.configuration(at: base() + "/redirect")
        XCTAssertEqual(config.sources.count, 3)
        XCTAssertEqual(config.sources.filter(\.isSupported).count, 2)
    }
    func testJSONBrowseSearchPaginationCategoryAndDetail() async throws {
        let client = TVClient()
        let source = Source(key: "test", name: "test", type: 1, api: try base() + "/json?token=test")
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.videos.count, 3); XCTAssertEqual(home.categories.count, 2)
        let search = try await client.browse(source: source, query: "第二部")
        XCTAssertEqual(search.videos.map(\.id), ["2"])
        let category = try await client.browse(source: source, category: "2")
        XCTAssertEqual(category.videos.map(\.id), ["2"])
        let page = try await client.browse(source: source, page: 2)
        XCTAssertEqual(page.page, 2)
        let video = try await client.detail(source: source, id: "1")
        XCTAssertEqual(video.id, "1"); XCTAssertEqual(video.lines.first?.episodes.count, 2)
    }
    func testXMLBrowseAndDetail() async throws {
        let client = TVClient()
        let source = Source(key: "xml", name: "xml", type: 0, api: try base() + "/xml")
        let page = try await client.browse(source: source)
        XCTAssertEqual(page.videos.count, 3)
        let video = try await client.detail(source: source, id: "2")
        XCTAssertEqual(video.id, "2"); XCTAssertEqual(video.lines.first?.episodes.count, 2)
    }
    func testHTTPError() async throws {
        let url = try URLTools.httpURL(base() + "/missing")
        do { _ = try await TVClient().fetch(url); XCTFail("404 must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("404")) }
    }
    func testResponseLimit() async throws {
        let url = try URLTools.httpURL(base() + "/oversize")
        do { _ = try await TVClient().fetch(url, limit: 512); XCTFail("Body must be limited") }
        catch { XCTAssertTrue(error.localizedDescription.contains("过大") || error.localizedDescription.contains("大小限制")) }
    }
    func testHTMLIsNotAConfiguration() async throws {
        let address = try base() + "/html"
        do { _ = try await TVClient().configuration(at: address); XCTFail("HTML must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("JSON")) }
    }
}
