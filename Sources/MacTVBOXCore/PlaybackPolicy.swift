import Foundation

/// Per-title offsets, never inferred from advertisements or a different title.
public struct PlaybackSkipSettings: Codable, Equatable {
    public var opening: Double
    public var ending: Double
    public init(opening: Double = 0, ending: Double = 0) {
        self.opening = Self.valid(opening); self.ending = Self.valid(ending)
    }
    private static func valid(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 900) : 0
    }
    public var normalized: Self { Self(opening: opening, ending: ending) }
}

public enum PlaybackPolicy {
    public static func startPosition(resume: Double, duration: Double, skips: PlaybackSkipSettings) -> Double {
        let resume = resume.isFinite ? max(0, resume) : 0
        guard duration.isFinite, duration > 0 else { return resume }
        let settings = skips.normalized
        let opening = settings.opening + settings.ending + 5 < duration ? settings.opening : 0
        // A completed title starts again; don't resume into its credits.
        let cutoff = settings.opening + settings.ending + 5 < duration ? max(3, settings.ending) : 3
        return max(opening, resume >= duration - cutoff ? 0 : resume)
    }
    public static func shouldFinish(position: Double, duration: Double, skips: PlaybackSkipSettings) -> Bool {
        let settings = skips.normalized
        return position.isFinite && duration.isFinite && settings.ending > 0
            && settings.opening + settings.ending + 5 < duration
            && position >= duration - settings.ending
    }
    public static func seekPosition(_ target: Double, duration: Double) -> Double? {
        guard target.isFinite, duration.isFinite, duration > 0 else { return nil }
        return min(max(0, target), duration)
    }
    public static func timeText(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "--:--" }
        let value = Int(min(time, 315_360_000))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
}
