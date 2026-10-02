@testable import FuseOSCore
import XCTest

@MainActor
final class DeviceTrustTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "DeviceTrustTests-\(UUID().uuidString)")
    }

    func testTheAccountsDevicesAtSignInAreTrustedAndPinned() {
        let trust = DeviceTrust(defaults: defaults)
        XCTAssertEqual(trust.check(deviceId: "phone", key: "k1"), .pending) // before any list
        trust.bootstrapIfNeeded(deviceIds: ["phone"])
        XCTAssertEqual(trust.check(deviceId: "phone", key: "k1"), .trusted)
        // Pinned: the same device with another key is asked about again.
        XCTAssertEqual(trust.check(deviceId: "phone", key: "k2"), .pending)
    }

    func testANewcomerWaitsForApprovalAndBlockingSticks() {
        let trust = DeviceTrust(defaults: defaults)
        trust.bootstrapIfNeeded(deviceIds: ["phone"])
        trust.bootstrapIfNeeded(deviceIds: ["phone", "stranger"]) // only the first list counts
        XCTAssertEqual(trust.check(deviceId: "stranger", key: "s"), .pending)
        trust.block(deviceId: "stranger", key: "s")
        XCTAssertEqual(trust.check(deviceId: "stranger", key: "s"), .blocked)
        trust.approve(deviceId: "stranger", key: "s")
        XCTAssertEqual(trust.check(deviceId: "stranger", key: "s"), .trusted)
    }

    func testItSurvivesARelaunchAndResetsOnSignOut() {
        let first = DeviceTrust(defaults: defaults)
        first.bootstrapIfNeeded(deviceIds: [])
        first.approve(deviceId: "mac", key: "m")
        let relaunched = DeviceTrust(defaults: defaults)
        XCTAssertEqual(relaunched.check(deviceId: "mac", key: "m"), .trusted)
        relaunched.reset()
        XCTAssertEqual(DeviceTrust(defaults: defaults).check(deviceId: "mac", key: "m"), .pending)
        XCTAssertFalse(DeviceTrust(defaults: defaults).bootstrapped)
    }
}
