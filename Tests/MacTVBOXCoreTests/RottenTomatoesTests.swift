import XCTest
@testable import MacTVBOXCore

final class RottenTomatoesTests: XCTestCase {
    func html(_ value: String) -> Data { Data(("<html><script>not executed()</script><script type='application/ld+json'>bad</script><script type=\"application/ld+json\">" + value + "</script></html>").utf8) }
    func testNestedCatalogPreservesOrderAndZeroScore() throws {
        let titles = try RankingClient.parseRottenTomatoes(html(#"{"@type":"ItemList","itemListElement":{"@type":"ItemList","itemListElement":[{"@type":"Movie","name":"A &amp; B","url":"https://www.rottentomatoes.com/m/a","dateCreated":"2026-09-01","image":"https://example.com/a.jpg","aggregateRating":{"name":"Tomatometer","ratingValue":"0"}},{"@type":"TVSeries","name":"Series","url":"https://www.rottentomatoes.com/tv/b","aggregateRating":{"name":"Tomatometer","ratingValue":99}}]}}"#))
        XCTAssertEqual(titles.map(\.id), ["rt:/m/a", "rt:/tv/b"])
        XCTAssertEqual(titles[0].score, "0%")
        XCTAssertEqual(titles[0].video.title, "A & B")
        XCTAssertEqual(titles[0].video.year, "2026")
        XCTAssertEqual(titles[1].video.remarks, "新鲜度 99%")
        XCTAssertTrue(titles.allSatisfy { $0.video.lines.isEmpty })
    }
    func testGraphListItemsUnknownScoreAndUnsafeURLs() throws {
        let titles = try RankingClient.parseRottenTomatoes(html(#"{"@graph":[{"@type":"ItemList","itemListElement":[{"@type":"ListItem","item":{"@type":"Movie","name":"A","url":"https://www.rottentomatoes.com/m/a","image":"javascript:bad","aggregateRating":{"name":"Popcornmeter","ratingValue":90}}},{"@type":"Movie","name":"dup","url":"https://www.rottentomatoes.com/m/a"},{"@type":"Movie","name":"bad","url":"https://www.rottentomatoes.com.evil.example/m/a"},{"@type":"Movie","name":"bad","url":"https://user@www.rottentomatoes.com/m/a"},{"@type":"Movie","name":"bad","url":"https://www.rottentomatoes.com/news/x"}]}]}"#))
        XCTAssertEqual(titles.count, 1)
        XCTAssertTrue(titles[0].score.isEmpty)
        XCTAssertTrue(titles[0].video.poster.isEmpty)
    }
    func testInvalidPagesNeverAppearAsSuccessfulEmptyRanking() {
        XCTAssertThrowsError(try RankingClient.parseRottenTomatoes(Data("<html>verification required</html>".utf8)))
        XCTAssertThrowsError(try RankingClient.parseRottenTomatoes(html(#"{"@type":"ItemList","itemListElement":[]}"#)))
    }
    func testProvidersDoNotShareCategoryIDsOrRatingScales() {
        let categories = RankingProvider.allCases.flatMap(\.categories)
        XCTAssertEqual(Set(categories.map(\.id)).count, 7)
        XCTAssertTrue(RankingCategory.rottenTomatoes.allSatisfy { $0.pageURL.host == "www.rottentomatoes.com" })
        XCTAssertEqual(RankingProvider.douban.categories.count, 4)
    }
    func testLiveRottenTomatoesPublicPages() async throws {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_RT"] == "1" else { throw XCTSkip("Optional public website smoke test") }
        for category in RankingCategory.rottenTomatoes {
            let result = try await RankingClient().fetch(category)
            XCTAssertFalse(result.items.isEmpty)
            XCTAssertTrue(result.items.allSatisfy { $0.subjectURL.host == "www.rottentomatoes.com" })
            print("RT public catalog: \(category.id), \(result.items.count) titles")
        }
    }
}
