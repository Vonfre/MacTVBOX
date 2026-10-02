import Foundation
import CommonCrypto
import Security

/// Bounded native protocol primitives; does not invoke openssl/Java or load plugins.
enum SpiderCrypto {
    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02X", $0) }.joined() }
    static func unhex(_ value: String) throws -> Data {
        guard !value.isEmpty, value.count <= 24 * 1024 * 1024, value.count % 2 == 0 else { throw SpiderFailure.format("加密响应长度无效。") }
        let chars = Array(value.utf8)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c { case 48...57: return c - 48; case 65...70: return c - 55; case 97...102: return c - 87; default: return nil }
        }
        var result = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let a = nibble(chars[i]), let b = nibble(chars[i + 1]) else { throw SpiderFailure.format("加密响应不是十六进制。") }
            result.append(a * 16 + b)
        }
        return result
    }
    static func md5(_ value: String) -> String {
        var result = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        Data(value.utf8).withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG($0.count), &result) }
        return hex(Data(result))
    }
    static func sha1(_ data: Data) -> Data {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG($0.count), &result) }
        return Data(result)
    }
    static func hmacSHA1(_ data: Data, key: String) -> Data {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        Data(key.utf8).withUnsafeBytes { key in data.withUnsafeBytes { input in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), key.baseAddress, key.count, input.baseAddress, input.count, &result)
        } }
        return Data(result)
    }
    static func javaHash(_ value: String) -> UInt32 { value.utf16.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) } }
    static func bigEndian(_ value: UInt32) -> Data { var value = value.bigEndian; return withUnsafeBytes(of: &value) { Data($0) } }
    static func nonce() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<16).map { _ in chars.randomElement()! })
    }
    /// Reads one definite-length DER object and rejects truncation/oversized lengths.
    private static func der(_ data: Data, offset: inout Int) throws -> (UInt8, Data) {
        let bytes = Array(data)
        guard offset + 2 <= bytes.count else { throw SpiderFailure.format("RSA 协议密钥格式无效。") }
        let tag = bytes[offset]; offset += 1
        let first = Int(bytes[offset]); offset += 1
        var count = first
        if first >= 128 {
            let n = first & 127
            guard (1...4).contains(n), offset + n <= bytes.count else { throw SpiderFailure.format("RSA DER 长度无效。") }
            count = 0
            for _ in 0..<n { count = count * 256 + Int(bytes[offset]); offset += 1 }
        }
        guard count <= bytes.count - offset else { throw SpiderFailure.format("RSA DER 内容截断。") }
        let result = Data(bytes[offset..<(offset + count)]); offset += count
        return (tag, result)
    }
    static func rsaKey(_ pem: String, privateKey: Bool) throws -> SecKey {
        let lines = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: lines), data.count < 16384 else { throw SpiderFailure.configuration("RSA 协议密钥不可读取。") }
        var offset = 0
        let (tag, body) = try der(data, offset: &offset)
        guard tag == 0x30, offset == data.count else { throw SpiderFailure.configuration("RSA 协议密钥不是完整 DER。") }
        var inner = 0
        let first = try der(body, offset: &inner)
        let raw: Data
        if privateKey {
            guard first.0 == 2 else { throw SpiderFailure.configuration("RSA 私钥格式无效。") }
            let algorithm = try der(body, offset: &inner)
            guard algorithm.0 == 0x30 else { throw SpiderFailure.configuration("RSA PKCS8 算法格式无效。") }
            let key = try der(body, offset: &inner)
            guard key.0 == 4 else { throw SpiderFailure.configuration("RSA PKCS8 内容无效。") }
            raw = key.1
        } else {
            guard first.0 == 0x30 else { throw SpiderFailure.configuration("RSA 公钥格式无效。") }
            let bits = try der(body, offset: &inner)
            guard bits.0 == 3, bits.1.first == 0 else { throw SpiderFailure.configuration("RSA SPKI 内容无效。") }
            raw = Data(bits.1.dropFirst())
        }
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(raw as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: privateKey ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic] as CFDictionary, &error) else {
            _ = error?.takeRetainedValue(); throw SpiderFailure.configuration("系统无法加载 RSA 协议密钥。")
        }
        return key
    }
    static func rsa(_ data: Data, pem: String, encrypt: Bool) throws -> Data {
        let key = try rsaKey(pem, privateKey: !encrypt)
        var error: Unmanaged<CFError>?
        let result = encrypt ? SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error) : SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error)
        guard let result else { _ = error?.takeRetainedValue(); throw SpiderFailure.format("RSA 协议数据解密或编码失败。") }
        return result as Data
    }
}
