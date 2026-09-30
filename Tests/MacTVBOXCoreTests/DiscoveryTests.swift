import XCTest
@testable import MacTVBOXCore

final class DiscoveryTests: XCTestCase {
    let sourceA = Source(key: "a", name: "A", type: 1, api: "https://example.com/a")
    let sourceB = Source(key: "b", name: "B", type: 1, api: "https://example.com/b")
    func testCollectionParserKeepsYearAndCastForMatching() throws {
        let data = Data(#"{"subject_collection_items":[{"id":"123","title":"测试影片","year":"2026","rating":{"value":8.2},"cover":{"url":"https://example.com/poster.jpg"},"directors":["导演"],"actors":["演员甲","演员乙"],"card_subtitle":"2026 / 剧情"},{"id":456,"title":"另一部","year":2025,"rating":{"value":0},"pic":{"large":"https://example.com/tv.jpg"}},{"id":"../unsafe","title":"bad"},{"id":"123","title":"duplicate"}]}"#.utf8)
        let titles = try RankingClient.parseCollection(data)
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles[0].video.year, "2026")
        XCTAssertEqual(titles[0].video.actors, "演员甲 / 演员乙")
        XCTAssertEqual(titles[0].score, "8.2")
        XCTAssertEqual(titles[1].video.year, "2025")
        XCTAssertTrue(titles[1].score.isEmpty)
        XCTAssertEqual(titles[1].video.poster, "https://example.com/tv.jpg")
        XCTAssertEqual(titles[0].subjectURL.absoluteString, "https://movie.douban.com/subject/123/")
        XCTAssertThrowsError(try RankingClient.parseCollection(Data("<html>验证</html>".utf8)))
        XCTAssertThrowsError(try RankingClient.parseCollection(Data(#"{"error":"login"}"#.utf8)))
    }
    func testRankingParserPreservesSourceOrderAndRating() throws {
        let data = Data(#"{"subjects":[{"id":"2","title":"剧集乙","cover":"https://example.com/b.jpg","rate":"8.8","url":"https://movie.douban.com/subject/2/"},{"id":"1","title":"电影甲","rate":"","url":"https://movie.douban.com/subject/1/","episodes_info":"更新至8集"}]}"#.utf8)
        let titles = try RankingClient.parse(data)
        XCTAssertEqual(titles.map(\.id), ["douban:2", "douban:1"])
        XCTAssertEqual(titles[0].score, "8.8")
        XCTAssertEqual(titles[1].video.remarks, "更新至8集")
        XCTAssertTrue(titles.allSatisfy { $0.video.lines.isEmpty })
    }
    func testRankingRejectsHTMLAndUntrustedLinks() throws {
        XCTAssertThrowsError(try RankingClient.parse(Data("<html>验证</html>".utf8)))
        let data = Data(#"{"subjects":[{"id":"1","title":"A","url":"https://evil.example/subject/1/"},{"id":"2","title":"B","url":"javascript:alert(1)"},{"id":"3","title":"C","url":"https://movie.douban.com/subject/3/"},{"id":"3","title":"C","url":"https://movie.douban.com/subject/3/"}]}"#.utf8)
        let titles = try RankingClient.parse(data)
        XCTAssertEqual(titles.count, 1)
        XCTAssertEqual(titles[0].video.title, "C")
    }
    func testGroupsDeduplicateSourcesButNeverMergeDifferentYearsOrSeasons() {
        let first = Video(id: "1", title: "庆余年", year: "2019")
        let second = Video(id: "2", title: "庆余年", year: "2019")
        let hits = [SourceMatch(video: first, source: sourceA), SourceMatch(video: first, source: sourceA),
                    SourceMatch(video: second, source: sourceB),
                    SourceMatch(video: Video(id: "3", title: "庆余年", year: "2024"), source: sourceA),
                    SourceMatch(video: Video(id: "4", title: "庆余年 第二季", year: "2024"), source: sourceA),
                    SourceMatch(video: Video(id: "5", title: "庆余年"), source: sourceB)]
        let groups = TitleMatcher.groups(hits)
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups.first { $0.video.year == "2019" }?.sourceCount, 2)
        XCTAssertEqual(groups.first { $0.video.year == "2019" }?.matches.count, 2)
    }
    func testMatchingConfidenceNeverPretendsUnknownYearIsVerified() {
        let target = Video(id: "x", title: "ＡＢＣ！", year: "2026")
        XCTAssertEqual(TitleMatcher.confidence(Video(id: "1", title: "abc", year: "2026"), for: target), 3)
        XCTAssertEqual(TitleMatcher.confidence(Video(id: "2", title: "abc"), for: target), 2)
        XCTAssertEqual(TitleMatcher.confidence(Video(id: "3", title: "abc", year: "1990"), for: target), 1)
        XCTAssertEqual(TitleMatcher.confidence(Video(id: "4", title: "ABC 第二季", year: "2026"), for: target), 0)
    }
    func testExactSearchMatchesRankAheadOfSimilarTitles() {
        XCTAssertEqual(TitleMatcher.relevance("给阿嬷的情书", query: "给阿嬷的情书"), 100)
        XCTAssertEqual(TitleMatcher.relevance("给阿嬷的情书 潮汕语版", query: "给阿嬷的情书"), 80)
        XCTAssertEqual(TitleMatcher.relevance("其他情书", query: "给阿嬷的情书"), 0)
        XCTAssertEqual(TitleMatcher.relevance("任意", query: ""), 0)
    }
    func testCategoriesHaveIndependentQueries() {
        XCTAssertEqual(RankingCategory.all.count, 4)
        XCTAssertEqual(Set(RankingCategory.all.map { $0.type + ":" + $0.tag }).count, 4)
    }
    func testLivePublicRankings() async throws {
        guard ProcessInfo.processInfo.environment["MACTVBOX_LIVE_RANKING"] == "1" else { throw XCTSkip("Opt in with MACTVBOX_LIVE_RANKING=1.") }
        for category in RankingCategory.all {
            let result = try await RankingClient().fetch(category)
            XCTAssertFalse(result.items.isEmpty)
            XCTAssertTrue(result.items.allSatisfy { !$0.video.poster.isEmpty })
            print("LIVE 豆瓣 \(category.title): \(result.items.count) entries, metadata only")
        }
    }
}
