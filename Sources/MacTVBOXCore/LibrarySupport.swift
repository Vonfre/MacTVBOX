import Foundation

extension SavedVideo {
    public var progressText: String {
        let seconds = Int(min(max(position.isFinite ? position : 0, 0), 315_360_000))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                               : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Suppress periodic updates after deletion until a new, explicit playback action.
public struct HistoryDeletionGuard {
    private var suppressed = Set<String>()
    public init() { }
    public mutating func delete(_ ids: Set<String>, from items: [SavedVideo]) -> [SavedVideo] {
        suppressed.formUnion(ids)
        return items.filter { !ids.contains($0.id) }
    }
    public mutating func beginPlayback(id: String) { suppressed.remove(id) }
    public func allowsRecording(id: String) -> Bool { !suppressed.contains(id) }
}
