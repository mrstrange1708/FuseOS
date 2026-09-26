@testable import FuseOSCore
import XCTest

final class NowPlayingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func track(playing: Bool, at ms: Int64 = 10_000, duration: Int64 = 60_000) -> NowPlaying {
        NowPlaying(appName: "App", title: "T", artist: "A", playing: playing,
                   positionMs: ms, positionAt: start, durationMs: duration, artwork: nil)
    }

    func testAdvancesWithTheClockWhilePlaying() {
        XCTAssertEqual(track(playing: true).position(at: start.addingTimeInterval(5)), 15_000)
    }

    func testStaysPutWhilePaused() {
        XCTAssertEqual(track(playing: false).position(at: start.addingTimeInterval(5)), 10_000)
    }

    func testNeverRunsPastTheEnd() {
        XCTAssertEqual(track(playing: true, at: 58_000).position(at: start.addingTimeInterval(10)), 60_000)
    }
}
