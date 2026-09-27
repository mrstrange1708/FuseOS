@testable import FuseOSCore
import XCTest

final class BeaconTokenTests: XCTestCase {
    /// The same vector as Android's BeaconTokenTest — the two must agree byte for byte.
    func testMatchesTheSharedVector() {
        let key = Data((0..<16).map(UInt8.init))
        XCTAssertEqual(BeaconToken.token(key: key, window: 2_900_000).map { String(format: "%02x", $0) }.joined(), "007dc1e4d2402c5a")
    }

    func testAcceptsThePreviousWindowForASlowClock() {
        let key = Data((0..<16).map(UInt8.init))
        let date = Date(timeIntervalSince1970: 2_900_000 * 600 + 5)
        XCTAssertTrue(BeaconToken.current(key: key, at: date).contains(BeaconToken.token(key: key, window: 2_899_999)))
    }
}
