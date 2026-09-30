import XCTest
@testable import MacTVBOXCore

final class PlaybackPolicyTests: XCTestCase {
    func testStartSkipsOpeningAndPreservesLaterResume() {
        let skips = PlaybackSkipSettings(opening: 90, ending: 120)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 0, duration: 2400, skips: skips), 90)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 35, duration: 2400, skips: skips), 90)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 500, duration: 2400, skips: skips), 500)
    }
    func testCompletedOrCreditsResumeStartsAgain() {
        let skips = PlaybackSkipSettings(opening: 90, ending: 120)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 2350, duration: 2400, skips: skips), 90)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 99999, duration: 2400, skips: skips), 90)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 99, duration: 100, skips: .init()), 0)
    }
    func testShortOrUnknownMediaDoesNotApplyOversizedSkips() {
        let skips = PlaybackSkipSettings(opening: 90, ending: 120)
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 10, duration: 30, skips: skips), 10)
        XCTAssertFalse(PlaybackPolicy.shouldFinish(position: 29, duration: 30, skips: skips))
        XCTAssertEqual(PlaybackPolicy.startPosition(resume: 12, duration: .nan, skips: skips), 12)
        XCTAssertFalse(PlaybackPolicy.shouldFinish(position: 500, duration: .infinity, skips: skips))
    }
    func testEndingBoundaryAndDisabledEnding() {
        let skips = PlaybackSkipSettings(opening: 10, ending: 30)
        XCTAssertFalse(PlaybackPolicy.shouldFinish(position: 69.9, duration: 100, skips: skips))
        XCTAssertTrue(PlaybackPolicy.shouldFinish(position: 70, duration: 100, skips: skips))
        XCTAssertFalse(PlaybackPolicy.shouldFinish(position: 100, duration: 100, skips: .init()))
        XCTAssertFalse(PlaybackPolicy.shouldFinish(position: .nan, duration: 100, skips: skips))
    }
    func testSettingsSanitizeAndPersist() throws {
        XCTAssertEqual(PlaybackSkipSettings(opening: -5, ending: .infinity), PlaybackSkipSettings())
        XCTAssertEqual(PlaybackSkipSettings(opening: 1000, ending: .nan), PlaybackSkipSettings(opening: 900))
        let value = PlaybackSkipSettings(opening: 85, ending: 110)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSkipSettings.self, from: JSONEncoder().encode(value)), value)
    }
    func testSeekBoundsAndUnknownDuration() {
        XCTAssertEqual(PlaybackPolicy.seekPosition(-5, duration: 120), 0)
        XCTAssertEqual(PlaybackPolicy.seekPosition(999, duration: 120), 120)
        XCTAssertEqual(PlaybackPolicy.seekPosition(50, duration: 120), 50)
        XCTAssertNil(PlaybackPolicy.seekPosition(.nan, duration: 120))
        XCTAssertNil(PlaybackPolicy.seekPosition(12, duration: .infinity))
        XCTAssertNil(PlaybackPolicy.seekPosition(12, duration: 0))
    }
    func testTimeFormatting() {
        XCTAssertEqual(PlaybackPolicy.timeText(.nan), "--:--")
        XCTAssertEqual(PlaybackPolicy.timeText(-1), "--:--")
        XCTAssertEqual(PlaybackPolicy.timeText(0), "00:00")
        XCTAssertEqual(PlaybackPolicy.timeText(65), "01:05")
        XCTAssertEqual(PlaybackPolicy.timeText(3661), "1:01:01")
    }
}
