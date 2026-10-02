import Foundation

/// Read-only migration of old ephemeral loopback bindings; no Android runtime remains.
public enum SourcePersistence {
    public static func isRetiredEndpoint(_ value: String?) -> Bool {
        guard let value, let url = URLComponents(string: value), url.scheme == "http", url.host == "127.0.0.1", url.path == "/api" else { return false }
        return url.queryItems?.contains { $0.name == "runtime" && $0.value == "mactvbox-android" } == true
    }
    public static func validBinding(_ value: String?) -> String? { isRetiredEndpoint(value) ? nil : value }
    public static func sanitized(_ source: Source) -> Source {
        var copy = source; copy.bridgeURL = validBinding(copy.bridgeURL); return copy
    }
    public static func sanitized(_ saved: SavedVideo) -> SavedVideo {
        var copy = saved; copy.source = sanitized(copy.source); return copy
    }
}
