@testable import FuseOSCore
import XCTest

final class UsageTests: XCTestCase {
    func testNamesTheFeatureAndNeverTheContent() {
        var clip = FuseEnvelope()
        clip.clipText = FuseClipText.with { $0.text = "my password" }
        let feature = Usage.feature(of: clip)
        XCTAssertEqual(feature?.name, "clipboard_text")
        XCTAssertFalse("\(String(describing: feature))".contains("my password"))

        var file = FuseEnvelope()
        file.fileMeta = FuseFileMeta.with { $0.name = "taxes.pdf"; $0.size = 2048 }
        XCTAssertEqual(Usage.feature(of: file), Usage.Feature("file_transfer", ["sizeBytes": 2048]))
    }

    func testPlumbingAndStopsAreNotFeatures() {
        var chunk = FuseEnvelope()
        chunk.fileChunk = FuseFileChunk.with { $0.data = Data("x".utf8) }
        XCTAssertNil(Usage.feature(of: chunk))

        var stop = FuseEnvelope()
        stop.screenControl = FuseScreenControl.with { $0.action = .stop }
        XCTAssertNil(Usage.feature(of: stop))

        var start = FuseEnvelope()
        start.screenControl = FuseScreenControl.with { $0.action = .start }
        XCTAssertEqual(Usage.feature(of: start)?.name, "screen_mirroring")
    }

    func testATrackpadSessionCountsOncePerWindow() {
        XCTAssertTrue(Usage.shouldCount("trackpad", now: 1_000_000))
        XCTAssertFalse(Usage.shouldCount("trackpad", now: 1_000_060))
        XCTAssertTrue(Usage.shouldCount("trackpad", now: 1_000_000 + 11 * 60))
        XCTAssertTrue(Usage.shouldCount("clipboard_text", now: 1_000_000))
        XCTAssertTrue(Usage.shouldCount("clipboard_text", now: 1_000_000))
    }
}
