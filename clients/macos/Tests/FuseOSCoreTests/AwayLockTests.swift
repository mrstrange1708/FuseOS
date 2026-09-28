@testable import FuseOSCore
import XCTest

final class AwayLockTests: XCTestCase {
    func testLocksWhenThePhoneIsFarAndOnlineSomewhereElse() {
        XCTAssertTrue(AwayLock.shouldLock(enabled: true, bluetoothFar: true, linkedNow: false, phoneOnlineViaServer: true))
    }

    func testLocksWhenThePhoneIsFarButStillOnThisWiFi() {
        XCTAssertTrue(AwayLock.shouldLock(enabled: true, bluetoothFar: true, linkedNow: true, phoneOnlineViaServer: true))
    }

    /// The bug found on the device: the link dropped with the phone on the desk and the Mac locked.
    func testNeverLocksOnALinkDropAloneWhileBluetoothHearsThePhone() {
        XCTAssertFalse(AwayLock.shouldLock(enabled: true, bluetoothFar: false, linkedNow: false, phoneOnlineViaServer: true))
    }

    func testDoesNotLockForAPhoneThatWentQuiet() {
        XCTAssertFalse(AwayLock.shouldLock(enabled: true, bluetoothFar: true, linkedNow: false, phoneOnlineViaServer: false))
    }

    func testDoesNotLockWhenOff() {
        XCTAssertFalse(AwayLock.shouldLock(enabled: false, bluetoothFar: true, linkedNow: false, phoneOnlineViaServer: true))
    }
}
