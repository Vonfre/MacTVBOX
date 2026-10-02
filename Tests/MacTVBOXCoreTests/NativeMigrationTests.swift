import XCTest
import Security
@testable import MacTVBOXCore

final class NativeMigrationTests: XCTestCase {
    func testNativeRegistryNeedsNoRuntime() {
        for api in ["csp_Jianpian", "csp_Gz360"] {
            let source = Source(key: api, name: api, type: 3, api: api)
            XCTAssertTrue(source.isSupported); XCTAssertFalse(source.usesHTTPSpider)
            XCTAssertEqual(source.requirement, .native)
        }
        let unknown = Source(key: "x", name: "x", type: 3, api: "csp_Unknown")
        XCTAssertFalse(unknown.isSupported); XCTAssertEqual(unknown.requirement, .unadapted)
    }
    func testRetiredEndpointMigrationPreservesLibraryAndExternalBindings() {
        var source = Source(key: "jp", name: "荐片", type: 3, api: "csp_Jianpian", ext: .string("https://api.example"))
        source.bridgeURL = "http://127.0.0.1:19978/api?token=old-secret&runtime=mactvbox-android"
        let episode = Episode(name: "第02集", address: "https://cdn.test/2.m3u8")
        let saved = SavedVideo(video: Video(id: "123", title: "Test"), source: source, episode: episode, position: 122)
        let cleaned = SourcePersistence.sanitized(saved)
        XCTAssertNil(cleaned.source.bridgeURL); XCTAssertFalse(source.usesHTTPSpider)
        XCTAssertEqual(cleaned.video, saved.video); XCTAssertEqual(cleaned.episode, saved.episode)
        XCTAssertEqual(cleaned.position, 122); XCTAssertEqual(cleaned.updatedAt, saved.updatedAt)
        XCTAssertEqual(cleaned.source.ext, saved.source.ext)
        for endpoint in ["http://127.0.0.1:7777/api", "https://external.test/api?token=my-own"] {
            source.bridgeURL = endpoint
            XCTAssertEqual(SourcePersistence.sanitized(source).bridgeURL, endpoint)
            XCTAssertTrue(source.usesHTTPSpider)
        }
    }
    func testJianpianResponseRejectsErrorsAndMalformedData() throws {
        XCTAssertEqual(try JianpianProvider.response(Data(#"{"code":1,"data":[]}"#.utf8))["code"] as? Int, 1)
        for body in ["{}", "[]", "<html>verification</html>", #"{"code":403,"data":[]}"#, #"{"code":1}"#] {
            XCTAssertThrowsError(try JianpianProvider.response(Data(body.utf8)))
        }
    }
    func testJianpianDetailsOnlyExposeSupportedHTTPMedia() throws {
        let item: [String: Any] = ["id": 123, "title": "<b>Example</b>", "thumbnail": "/cover.jpg", "year": 2026,
            "actors": [["name": "Actor"]], "description": "<p>Summary</p>",
            "source_list_source": [
                ["name": "专有", "source_list": [["source_name": "1", "url": "ftp://cdn.test/film"]]],
                ["name": "网页", "source_list": [["source_name": "1", "url": "https://example.test/play.html"]]],
                ["name": "蓝光", "source_list": [["source_name": "第01集", "url": "https://cdn.test/1.m3u8?token=x"], ["source_name": "第02集", "url": "https://cdn.test/2.mp4"]]]
            ]]
        let video = try JianpianProvider.detail(item, imageBase: URL(string: "https://images.test"))
        XCTAssertEqual(video.id, "123"); XCTAssertEqual(video.title, "Example")
        XCTAssertEqual(video.poster, "https://images.test/cover.jpg"); XCTAssertEqual(video.year, "2026")
        XCTAssertEqual(video.actors, "Actor"); XCTAssertEqual(video.lines.count, 1)
        XCTAssertEqual(video.lines[0].episodes.count, 2)
        let provider = JianpianProvider(client: TVClient(), source: Source(key: "jp", name: "jp", type: 3, api: "csp_Jianpian"))
        let media = try provider.resolve(video.lines[0].episodes[0])
        XCTAssertEqual(media.headers["X-Requested-With"], "com.jp3.xg3")
        XCTAssertNil(media.headers["Cookie"])
        XCTAssertThrowsError(try provider.resolve(Episode(name: "x", address: "ftp://cdn.test/x")))
        XCTAssertThrowsError(try provider.resolve(Episode(name: "x", address: "https://cdn.test/page.html")))
        XCTAssertThrowsError(try JianpianProvider.detail(["id": 1, "title": "Empty", "source_list_source": []], imageBase: nil))
    }
    func testGuaziQualitiesPreserveOrderingAndRejectEmptyParameters() throws {
        let payload: [String: Any] = ["list": [
            ["title": "01", "play": ["1080": ["param": "vod_d_id=42&url_id=1"], "720": ["param": "vod_d_id=42&url_id=2"]]],
            ["title": "02", "play": ["1080": ["param": "vod_d_id=42&url_id=3"], "720": ["param": ""]]],
            ["title": "bad", "play": ["2160": ["param": "not-a-query"]]]
        ]]
        let lines = try GuaziProvider.lines(payload)
        XCTAssertEqual(lines.map(\.name), ["瓜子 · 1080P", "瓜子 · 720P"])
        XCTAssertEqual(lines[0].episodes.map(\.name), ["01 [1080P]", "02 [1080P]"])
        XCTAssertEqual(lines[1].episodes.count, 1)
        XCTAssertThrowsError(try GuaziProvider.lines(["list": []]))
        XCTAssertThrowsError(try GuaziProvider.lines([:]))
        XCTAssertEqual(try GuaziProvider.parameters("vod_d_id=42&url=abc=def")["vod_id"], "42")
        XCTAssertEqual(try GuaziProvider.parameters("vod_d_id=42&url=abc=def")["url"], "abc=def")
        for value in ["", "bad", "vod_id=", "vod_id=1&vod_id=2", "id=1"] { XCTAssertThrowsError(try GuaziProvider.parameters(value)) }
    }
    func testGuaziListRejectsMissingFieldsButAcceptsEmptyResults() throws {
        XCTAssertTrue(try GuaziProvider.list(["list": []], page: 2).videos.isEmpty)
        XCTAssertThrowsError(try GuaziProvider.list([:], page: 1))
        XCTAssertThrowsError(try GuaziProvider.list(["list": [["vod_id": "1"]]], page: 1))
        let page = try GuaziProvider.list(["list": [["vod_id": 2, "vod_name": "Example", "vod_pic": "https://cdn.test/a.jpg"]]], page: 1)
        XCTAssertEqual(page.videos.first?.id, "2")
    }
    func testProtocolPrimitivesAndForms() throws {
        XCTAssertEqual(SpiderCrypto.md5("abc"), "900150983CD24FB0D6963F7D28E17F72")
        XCTAssertEqual(SpiderCrypto.hex(SpiderCrypto.sha1(Data("abc".utf8))), "A9993E364706816ABA3E25717850C26C9CD0D89D")
        XCTAssertEqual(SpiderCrypto.javaHash("abc"), 96354)
        XCTAssertEqual(SpiderCrypto.hex(SpiderCrypto.bigEndian(0x1234abcd)), "1234ABCD")
        XCTAssertEqual(try SpiderCrypto.unhex("00aAFF"), Data([0, 170, 255]))
        for value in ["", "0", "GG", "FF 0"] { XCTAssertThrowsError(try SpiderCrypto.unhex(value)) }
        XCTAssertEqual(String(decoding: GuaziProvider.form([("key", "a+b/c== &中")]), as: UTF8.self), "key=a%2Bb%2Fc%3D%3D%20%26%E4%B8%AD")
        XCTAssertThrowsError(try SpiderCrypto.rsaKey("broken", privateKey: true))
    }
    func testGuaziEnvelopeSignatureAndRandomness() throws {
        let fields = try GuaziProvider.envelope(["keywords": "a+b"], token: "test-session", time: 42)
        XCTAssertEqual(fields.prefix(7).map(\.0), ["token_id", "token", "phone_type", "request_key", "app_id", "time", "keys"])
        let expected = SpiderCrypto.md5(fields.prefix(7).map { $0.0 + "=" + $0.1 }.joined(separator: ",") + "*&zvdvdvddbfikkkumtmdwqppp?|4Y!s!2br")
        XCTAssertEqual(fields.first { $0.0 == "signature" }?.1, expected)
        XCTAssertEqual(fields.first { $0.0 == "time" }?.1, "42")
        let second = try GuaziProvider.envelope(["keywords": "a+b"], token: "test-session", time: 42)
        XCTAssertNotEqual(fields.first { $0.0 == "request_key" }?.1, second.first { $0.0 == "request_key" }?.1)
    }
    func testGuaziEncryptedResponseRoundTripAndRejections() throws {
        let secret = "1234567890abcdef", iv = "fedcba0987654321"
        let payload = Data(#"{"list":[],"count":0}"#.utf8)
        let cipher = try AppGetProvider.aes(payload, key: Data(secret.utf8), iv: Data(iv.utf8), encrypt: true)
        let privateKey = try SpiderCrypto.rsaKey(GuaziProtocol.responsePrivateKey, privateKey: true)
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let info = try JSONSerialization.data(withJSONObject: ["key": secret, "iv": iv])
        var error: Unmanaged<CFError>?
        let encrypted = try XCTUnwrap(SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1, info as CFData, &error)) as Data
        let result = try GuaziProvider.decoded(["code": 200, "data": ["response_key": SpiderCrypto.hex(cipher), "keys": encrypted.base64EncodedString()]])
        XCTAssertEqual(result["count"] as? Int, 0)
        for value: [String: Any] in [["code": 401], ["code": 403], ["code": 500], ["code": 200], ["code": 200, "data": ["response_key": "GG", "keys": "bad"]]] {
            XCTAssertThrowsError(try GuaziProvider.decoded(value))
        }
    }
    func testGuaziConflictingIDsRejected() throws {
        XCTAssertThrowsError(try GuaziProvider.parameters("vod_d_id=1&vod_id=2&url_id=3"))
        XCTAssertEqual(try GuaziProvider.parameters("vod_d_id=1&vod_id=1&url_id=3")["vod_id"], "1")
    }
    func testGuaziSessionReuseAndInvalidation() async throws {
        let sessions = GuaziSessions()
        let one = try await sessions.session(key: "https://a.test") { GuaziAuth(token: "a", userID: "1", referer: "https://a.test", created: Date()) }
        let reused = try await sessions.session(key: "https://a.test") { throw TVError.message("Should not refresh") }
        XCTAssertEqual(one.token, reused.token)
        await sessions.invalidate(key: "https://a.test", token: "stale")
        let preserved = try await sessions.session(key: "https://a.test") { throw TVError.message("Stale failure must not invalidate a newer session") }
        XCTAssertEqual(preserved.token, "a")
        await sessions.invalidate(key: "https://a.test", token: "a")
        let refreshed = try await sessions.session(key: "https://a.test") { GuaziAuth(token: "b", userID: "2", referer: "https://a.test", created: Date()) }
        XCTAssertEqual(refreshed.token, "b")
        let separate = try await sessions.session(key: "https://b.test") { GuaziAuth(token: "c", userID: "3", referer: "https://b.test", created: Date()) }
        XCTAssertEqual(separate.token, "c")
    }
}
