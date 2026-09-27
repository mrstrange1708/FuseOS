@testable import FuseOSCore
import XCTest

final class SidecarLinkTests: XCTestCase {
    func testDecodesTouchesAndClampsToTheDisplay() {
        XCTAssertEqual(SidecarLink.touch(from: .with { $0.kind = .tap; $0.x = 0.25; $0.y = 0.5 }), .tap(x: 0.25, y: 0.5))
        XCTAssertEqual(SidecarLink.touch(from: .with { $0.kind = .move; $0.x = 1.4; $0.y = -0.2 }), .move(x: 1, y: 0))
        XCTAssertEqual(
            SidecarLink.touch(from: .with { $0.kind = .scroll; $0.x = 0.5; $0.y = 0.5; $0.dx = 2; $0.dy = -8 }),
            .scroll(x: 0.5, y: 0.5, dx: 2, dy: -8),
        )
    }

    func testIgnoresAnUnknownKind() {
        XCTAssertNil(SidecarLink.touch(from: FuseSidecarInput()))
    }
}
