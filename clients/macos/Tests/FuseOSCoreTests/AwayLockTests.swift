@testable import FuseOSCore
import XCTest

final class AwayLockTests: XCTestCase {
    private func lock(far: Bool = true, linked: Bool, confirmed: Bool = false, elsewhere: Bool = false, enabled: Bool = true) -> Bool {
        AwayLock.shouldLock(enabled: enabled, bluetoothFar: far, linkedNow: linked,
                            checkConfirmedFar: confirmed, phoneOnAnotherNetwork: elsewhere)
    }

    func testLocksWhenThePhoneIsFarAndOnAnotherNetwork() {
        XCTAssertTrue(lock(linked: false, elsewhere: true))
    }

    func testLocksOnThisWiFiOnlyOnceTheBeaconCheckAgrees() {
        XCTAssertTrue(lock(linked: true, confirmed: true))
    }

    /// The bug found on the device: a throttled beacon read far with the phone on the desk,
    /// still linked, and the Mac locked.
    func testBluetoothAloneNeverLocksALinkedPhone() {
        XCTAssertFalse(lock(linked: true, confirmed: false, elsewhere: true))
    }

    /// And the earlier one: the link dropped with the phone on the desk.
    func testNeverLocksOnALinkDropAloneWhileBluetoothHearsThePhone() {
        XCTAssertFalse(lock(far: false, linked: false, elsewhere: true))
    }

    func testDoesNotLockAPhoneStillOnThisWiFiWithTheLinkDown() {
        XCTAssertFalse(lock(linked: false, elsewhere: false))
    }

    func testDoesNotLockWhenOff() {
        XCTAssertFalse(lock(linked: false, elsewhere: true, enabled: false))
    }

    func testSameNetworkComparesTheSlash24() {
        XCTAssertTrue(AwayLock.sameNetwork("192.168.1.20:5000", "192.168.1.7:6000"))
        XCTAssertFalse(AwayLock.sameNetwork("192.168.1.20:5000", "10.0.0.7:6000"))
        XCTAssertFalse(AwayLock.sameNetwork(nil, "192.168.1.7:6000"))
        XCTAssertFalse(AwayLock.sameNetwork("", "192.168.1.7:6000"))
    }
}
