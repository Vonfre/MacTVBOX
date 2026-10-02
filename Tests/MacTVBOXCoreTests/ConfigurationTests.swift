import XCTest
@testable import MacTVBOXCore

final class ConfigurationTests: XCTestCase {
    func parse(_ value: String) throws -> TVConfiguration { try ConfigurationParser.parse(Data(value.utf8), baseURL: URL(string: "https://example.com/config/main.json")) }
    func testStandardConfig() throws {
        let config = try parse(#"{"sites":[{"key":"a","name":"影院","type":1,"api":"https://example.com/api"},{"key":"b","name":"插件","type":3,"api":"csp_X"}],"spider":"https://example.com/plugin.jar"}"#)
        XCTAssertEqual(config.sources.count, 2)
        XCTAssertTrue(config.sources[0].isSupported)
        XCTAssertFalse(config.sources[1].isSupported)
        XCTAssertEqual(config.spider, "https://example.com/plugin.jar")
    }
    func testJSONCDoesNotStripURLOrCommentLikeStrings() throws {
        let config = try parse("""
        // document comment
        {"sites":[{"key":"a", "name":"https://x/*text*/", "type":1, /* inline */ "api":"https://example.com/a",},],}
        """)
        XCTAssertEqual(config.sources[0].api, "https://example.com/a")
        XCTAssertEqual(config.sources[0].name, "https://x/*text*/")
    }
    func testKnownMissingQuoteRepairIsReported() throws {
        let config = try parse("""
        {"sites":[{"key":"a","type":3,"api":"csp_Test",
        ext": {"host":"https://example.com"}}, {"key":"b","type":3,"api":"csp_Test2",
        ext": {"host":"http://example.com"}}]}
        """)
        XCTAssertEqual(config.sources.count, 2)
        XCTAssertTrue(config.warnings.contains { $0.contains("2 处") })
        XCTAssertTrue(config.warnings.contains { $0.contains("没有已适配") })
    }
    func testQuotedContentNotRepaired() throws {
        let config = try parse(#"{"sites":[{"key":"a","name":"literal\next\": string","type":1,"api":"https://example.com"}]}"#)
        XCTAssertTrue(config.warnings.isEmpty)
    }
    func testDuplicatesAndInvalidEntries() throws {
        let config = try parse(#"{"sites":[{"key":"a","api":"https://example.com","type":"1"},{"key":"a","api":"https://other.example","type":1},{"key":"b"}]}"#)
        XCTAssertEqual(config.sources.count, 1)
        XCTAssertEqual(config.warnings.count, 2)
    }
    func testUnsupportedUnknownTypeNotTreatedAsXML() throws {
        let config = try parse(#"{"sites":[{"api":"https://example.com"}]}"#)
        XCTAssertFalse(config.sources[0].isSupported)
        XCTAssertEqual(config.sources[0].type, -1)
    }
    func testRelativeAndSearchable() throws {
        let config = try parse(#"{"sites":[{"key":"a","type":1,"api":"../api","searchable":0}]}"#)
        XCTAssertEqual(config.sources[0].api, "https://example.com/api")
        XCTAssertFalse(config.sources[0].searchable)
    }
    func testInvalidInputsRejected() {
        for value in ["<html>error</html>", "{}", "{\"sites\":[]}", "garbage"] { XCTAssertThrowsError(try parse(value)) }
    }
    func testBOM() throws { XCTAssertEqual(try parse("\u{feff}{\"sites\":[{\"api\":\"https://example.com\",\"type\":1}]}").sources.count, 1) }
    func testPayloadLimit() { XCTAssertThrowsError(try ConfigurationParser.parse(Data(repeating: 32, count: 8 * 1024 * 1024 + 1))) }
    func testProvidedConfigurationSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["MACTVBOX_CONFIG_FIXTURE"] else { throw XCTSkip("Set MACTVBOX_CONFIG_FIXTURE to inspect a downloaded provider configuration.") }
        let config = try ConfigurationParser.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(config.sources.isEmpty)
        print("Provider inspection: \(config.sources.count) sources; native \(config.sources.filter(\.isSupported).count); warnings \(config.warnings)")
    }
}
