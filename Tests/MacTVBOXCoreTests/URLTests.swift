import XCTest
@testable import MacTVBOXCore

final class URLTests: XCTestCase {
    func testInternationalDomain() throws {
        let url = try URLTools.httpURL("http://肥猫.net")
        XCTAssertTrue(url.absoluteString.contains("xn--z7x900a.net"))
    }
    func testUnsafeSchemesAndCredentialsRejected() {
        for value in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com", "https://user:pass@example.com", "", "肥猫.net"] { XCTAssertThrowsError(try URLTools.httpURL(value)) }
    }
    func testQueryEncodingAndStaleParameterReplacement() throws {
        let url = try URLTools.apiURL("https://example.com/api?token=abc&wd=old&pg=99&ac=list&t=8&ids=6", parameters: ["ac": "detail", "wd": "电影 & test+好", "pg": "1"])
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.filter { $0.name == "wd" }.count, 1)
        XCTAssertEqual(items.first { $0.name == "wd" }?.value, "电影 & test+好")
        XCTAssertEqual(items.first { $0.name == "token" }?.value, "abc")
        XCTAssertNil(items.first { $0.name == "ids" }); XCTAssertNil(items.first { $0.name == "t" })
    }
    func testProtocolRelativeURL() { XCTAssertEqual(URLTools.resolved("//example.com/p.jpg", relativeTo: URL(string: "http://example.com")), "http://example.com/p.jpg") }
}
