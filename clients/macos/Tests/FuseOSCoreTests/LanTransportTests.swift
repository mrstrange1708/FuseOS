@testable import FuseOSCore
import Foundation
import Network
import XCTest

/// The two decisions that determine whether a pair of devices connects at all.
///
/// Both fail silently when wrong: a broken tie-break means either nobody dials or both
/// do, and a broken address parse means the dial never leaves the building. Neither
/// throws anything a user or a log would show.
@MainActor
final class LanTransportTests: XCTestCase {

    // MARK: - Who dials

    /// Exactly one side must dial. If both do, a pair ends up with two half-used
    /// connections; if neither does, they never meet.
    func testExactlyOneSideOfAPairDials() {
        let a = "11111111-aaaa", b = "99999999-zzzz"
        XCTAssertTrue(LanTransport.dialsFirst(selfId: a, peerId: b))
        XCTAssertFalse(LanTransport.dialsFirst(selfId: b, peerId: a))

        // Stated as the property itself: for any pair, exactly one dials.
        XCTAssertNotEqual(
            LanTransport.dialsFirst(selfId: a, peerId: b),
            LanTransport.dialsFirst(selfId: b, peerId: a),
        )
    }

    /// Real device ids are UUIDs from Postgres. Spot-check the property holds on values
    /// of that actual shape rather than on tidy fixtures.
    func testTieBreakHoldsForRealisticUuidPairs() {
        for _ in 0 ..< 100 {
            let x = UUID().uuidString, y = UUID().uuidString
            guard x != y else { continue }
            XCTAssertNotEqual(
                LanTransport.dialsFirst(selfId: x, peerId: y),
                LanTransport.dialsFirst(selfId: y, peerId: x),
            )
        }
    }

    /// Degenerate but worth pinning: a device must never decide to dial itself.
    func testADeviceDoesNotDialItself() {
        let id = UUID().uuidString
        XCTAssertFalse(LanTransport.dialsFirst(selfId: id, peerId: id))
    }

    /// The comparison must agree with Android's Kotlin `selfId < peerId`, which is
    /// ordinal by UTF-16 code unit. Case matters and uppercase sorts first — if one
    /// platform ever compared case-insensitively the two would both dial or both wait.
    func testOrderingIsOrdinalNotLocaleSensitive() {
        XCTAssertTrue(LanTransport.dialsFirst(selfId: "A-device", peerId: "a-device"))
        XCTAssertFalse(LanTransport.dialsFirst(selfId: "a-device", peerId: "A-device"))
    }

    // MARK: - Address parsing

    func testParsesAHostAndPort() throws {
        let parsed = try XCTUnwrap(LanTransport.parseAddress("192.168.1.20:47100"))
        XCTAssertEqual(parsed.0, "192.168.1.20")
        XCTAssertEqual(parsed.1.rawValue, 47100)
    }

    func testParsesTheEphemeralPortRange() throws {
        let low = try XCTUnwrap(LanTransport.parseAddress("10.0.0.1:1"))
        XCTAssertEqual(low.1.rawValue, 1)
        let high = try XCTUnwrap(LanTransport.parseAddress("10.0.0.1:65535"))
        XCTAssertEqual(high.1.rawValue, 65535)
    }

    /// A peer's lanAddress arrives over the network. Anything malformed must come back
    /// nil so the dial is skipped, never crash or produce a bogus endpoint.
    func testRejectsMalformedAddresses() {
        for bad in [
            "",                     // empty
            "192.168.1.20",         // no port
            ":47100",               // no host
            "192.168.1.20:",        // no port digits
            "192.168.1.20:abc",     // non-numeric port
            "192.168.1.20:0",       // port 0 is not dialable
            "192.168.1.20:65536",   // out of range
            "192.168.1.20:-1",      // negative
            "not an address at all",
        ] {
            XCTAssertNil(LanTransport.parseAddress(bad), "should have rejected \(bad.debugDescription)")
        }
    }

    /// Splitting on the LAST colon is what makes a bracketed IPv6 literal survive. Worth
    /// pinning even though the transport advertises IPv4 today, because splitting on the
    /// first colon would look correct in every IPv4 test and break the moment it is not.
    func testSplitsOnTheFinalColonSoIpv6LiteralsSurvive() throws {
        let parsed = try XCTUnwrap(LanTransport.parseAddress("[fe80::1]:47100"))
        XCTAssertEqual(parsed.0, "[fe80::1]")
        XCTAssertEqual(parsed.1.rawValue, 47100)
    }

    // MARK: - Lifecycle

    func testLanAddressIsNilBeforeTheListenerIsUp() {
        XCTAssertNil(LanTransport().lanAddress())
    }

    func testSequenceNumbersAreMonotonicWithinADevice() {
        // Loop prevention on the receiving side depends on this never going backwards.
        let transport = LanTransport()
        let first = transport.newEnvelope().seq
        let second = transport.newEnvelope().seq
        let third = transport.newEnvelope().seq
        XCTAssertLessThan(first, second)
        XCTAssertLessThan(second, third)
    }

    func testStopIsSafeToCallWithoutStarting() {
        // Sign-out can land before bootstrap finishes.
        let transport = LanTransport()
        transport.stop()
        XCTAssertTrue(transport.connectedPeers.isEmpty)
    }

    func testUpdatingPeersBeforeStartDoesNotDial() {
        // Presence can arrive before the device id is known; it must be ignored, not
        // dialed with an empty identity.
        let transport = LanTransport()
        transport.updatePeers([
            "peer": PeerPresence(online: true, battery: 50, publicKey: "x", lanAddress: "1.2.3.4:1"),
        ])
        XCTAssertTrue(transport.connectedPeers.isEmpty)
    }
}
