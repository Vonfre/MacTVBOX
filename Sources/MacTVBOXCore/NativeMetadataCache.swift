import Foundation

/// Small client-scoped cache for optional poster-host metadata. No credentials are cached here.
actor NativeMetadataCache {
    private struct Entry { let value: URL?; let expires: Date }
    private var entries: [String: Entry] = [:]
    private var pending: [String: Task<URL?, Never>] = [:]
    func url(key: String, load: @escaping () async -> URL?) async -> URL? {
        if let entry = entries[key], entry.expires > Date() { return entry.value }
        if let task = pending[key] { return await task.value }
        let task = Task { await load() }; pending[key] = task
        let value = await task.value
        if entries.count >= 64 { entries.removeAll() }
        entries[key] = Entry(value: value, expires: Date().addingTimeInterval(value == nil ? 30 : 900))
        pending[key] = nil
        return value
    }
}
