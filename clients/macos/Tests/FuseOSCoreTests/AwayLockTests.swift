@testable import FuseOSCore
import XCTest

final class AwayLockTests: XCTestCase {
    func testLocksWhenThePhoneIsOnlineSomewhereElse() {
        XCTAssertTrue(AwayLock.shouldLock(enabled: true, linkedNow: false, phoneOnlineViaServer: true))
    }

    func testDoesNotLockForAPhoneThatWentQuiet() {
        XCTAssertFalse(AwayLock.shouldLock(enabled: true, linkedNow: false, phoneOnlineViaServer: false))
    }

    func testDoesNotLockWhileLinkedOrWhenOff() {
        XCTAssertFalse(AwayLock.shouldLock(enabled: true, linkedNow: true, phoneOnlineViaServer: true))
        XCTAssertFalse(AwayLock.shouldLock(enabled: false, linkedNow: false, phoneOnlineViaServer: true))
    }
}
