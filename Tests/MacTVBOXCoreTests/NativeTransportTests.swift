import XCTest
import Security
@testable import MacTVBOXCore

private final class NativeFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "native-fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let data = try Self.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    static func response(_ request: URLRequest) throws -> Data {
        let url = request.url!, path = url.path
        var value: [String: Any]
        if path.hasPrefix("/jp/") {
            guard request.httpMethod == "GET", request.value(forHTTPHeaderField: "X-Requested-With") == "com.jp3.xg3" else { throw TVError.message("Bad native JP headers") }
            let video: [String: Any] = ["id": 42, "jump_id": 42, "title": "Example", "thumbnail": "/cover.jpg"]
            switch path {
            case "/jp/api/v2/settings/packageDomainConfig": value = ["imgDomain": "images.test"]
            case "/jp/api/video/detailv2":
                var item = video
                item["source_list_source"] = [["name": "蓝光", "source_list": [["source_name": "01", "url": "https://media.test/1.m3u8"]]]]
                value = ["code": 1, "data": item]
                return try JSONSerialization.data(withJSONObject: value)
            default:
                let data: Any
                if path.hasSuffix("home_fenlei") { data = [["id": 1, "name": "电影"]] }
                else {
                    if path.contains("videoV2") {
                        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
                        guard items.first(where: { $0.name == "key" })?.value == "片名 + & 中文" else { throw TVError.message("JP query incorrectly encoded") }
                    }
                    data = [video]
                }
                return try JSONSerialization.data(withJSONObject: ["code": 1, "data": data, "total": 1])
            }
            return try JSONSerialization.data(withJSONObject: ["code": 1, "data": value])
        }
        guard path.hasPrefix("/gz/App/"), request.httpMethod == "POST", request.value(forHTTPHeaderField: "code") == "GZ0313" else { throw TVError.message("Unexpected fixture request") }
        if path.contains("Authentication/") { value = ["token": "fixture-token", "app_user_id": "12"] }
        else if path.hasSuffix("getUserInfo") { value = ["playRef": "https://referer.test/"] }
        else if path.hasSuffix("playInfo") { value = ["vodInfo": ["vod_id": 42, "vod_name": "Example"]] }
        else if path.hasSuffix("Vurl/show") { value = ["list": [["title": "01", "play": ["1080": ["param": "vod_d_id=42&url_id=123"]]]]] }
        else if path.hasSuffix("showOne") { value = ["url": "https://media.test/1.m3u8"] }
        else { value = ["list": [["vod_id": 42, "vod_name": "Example"]]] }
        let key = "abcdefghijklmnop", iv = "ponmlkjihgfedcba"
        let encrypted = try AppGetProvider.aes(JSONSerialization.data(withJSONObject: value), key: Data(key.utf8), iv: Data(iv.utf8), encrypt: true)
        let publicKey = SecKeyCopyPublicKey(try SpiderCrypto.rsaKey(GuaziProtocol.responsePrivateKey, privateKey: true))!
        let wrapped = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1, try JSONSerialization.data(withJSONObject: ["key": key, "iv": iv]) as CFData, nil)! as Data
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["keys": wrapped.base64EncodedString(), "response_key": SpiderCrypto.hex(encrypted)]])
    }
}

final class NativeTransportTests: XCTestCase {
    private func client() -> TVClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NativeFixtureProtocol.self]
        return TVClient(session: URLSession(configuration: config))
    }
    func testJianpianNativeTransportThroughTVClient() async throws {
        let client = client(), source = Source(key: "jp", name: "JP", type: 3, api: "csp_Jianpian", ext: .string("https://native-fixture.test/jp"))
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.categories.first?.name, "电影"); XCTAssertEqual(home.videos.first?.id, "42")
        let results = try await client.browse(source: source, query: "片名 + & 中文")
        XCTAssertEqual(results.pageCount, 1)
        let detail = try await client.detail(source: source, id: "42")
        XCTAssertEqual(detail.poster, "https://images.test/cover.jpg")
        let media = try await client.resolve(source: source, episode: detail.lines[0].episodes[0])
        XCTAssertEqual(media.url.absoluteString, "https://media.test/1.m3u8")
    }
    func testGuaziNativeEncryptedTransportThroughTVClient() async throws {
        let client = client(), source = Source(key: "gz", name: "GZ", type: 3, api: "csp_Gz360", ext: .object(["sites": .string("https://native-fixture.test/gz")]))
        let home = try await client.browse(source: source)
        XCTAssertEqual(home.categories.count, 5); XCTAssertEqual(home.videos.first?.id, "42")
        let category = try await client.browse(source: source, category: "2")
        XCTAssertEqual(category.videos.first?.title, "Example")
        let results = try await client.browse(source: source, query: "片名 + & 中文")
        XCTAssertEqual(results.pageCount, 1)
        let detail = try await client.detail(source: source, id: "42")
        XCTAssertEqual(detail.lines[0].name, "瓜子 · 1080P")
        let media = try await client.resolve(source: source, episode: detail.lines[0].episodes[0])
        XCTAssertEqual(media.url.absoluteString, "https://media.test/1.m3u8")
        XCTAssertEqual(media.headers["Referer"], "https://referer.test/")
        XCTAssertNil(media.headers["token"])
    }
}
