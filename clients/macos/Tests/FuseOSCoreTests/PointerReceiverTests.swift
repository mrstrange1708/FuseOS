@testable import FuseOSCore
import XCTest

final class PointerReceiverTests: XCTestCase {
    func testDecodesEachKind() {
        XCTAssertEqual(PointerReceiver.event(from: .with { $0.kind = .move; $0.dx = 3; $0.dy = -2 }), .move(dx: 3, dy: -2))
        XCTAssertEqual(PointerReceiver.event(from: .with { $0.kind = .rightClick }), .rightClick)
        XCTAssertEqual(PointerReceiver.event(from: .with { $0.kind = .text; $0.text = "hi" }), .text("hi"))
        XCTAssertEqual(
            PointerReceiver.event(from: .with { $0.kind = .key; $0.keyCode = 36; $0.modifiers = 1 }),
            .key(code: 36, modifiers: 1),
        )
    }

    func testDropsWhatCannotBeActedOn() {
        XCTAssertNil(PointerReceiver.event(from: .with { $0.kind = .text }))
        XCTAssertNil(PointerReceiver.event(from: FusePointerInput()))
    }
}
