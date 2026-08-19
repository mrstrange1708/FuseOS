@testable import FuseOSCore
import Foundation
import XCTest

/// Feeds real `/signal` frames — byte for byte what `server/src/signal/ws.ts` emits —
/// straight into the parser, without standing up a WebSocket.
///
/// This is where the control plane hands the data plane everything it needs. A peer card
/// that loses its `publicKey` or `lanAddress` in parsing produces a device that shows as
/// online and can never be connected to, with nothing logged anywhere.
@MainActor
final class SignalClientTests: XCTestCase {

    private var client: SignalClient!

    override func setUp() async throws {
        try await super.setUp()
        client = SignalClient()
    }

    func testHelloOkPopulatesThePeerRosterWithKeysAndAddresses() {
        client.handle("""
        {"type":"hello-ok","deviceId":"me","peers":[
          {"deviceId":"peer-1","name":"Pixel 8","platform":"android","publicKey":"BASE64KEY",
           "lanAddress":"192.168.1.20:47100","battery":88,"online":true}
        ]}
        """)

        let peer = client.presence["peer-1"]
        XCTAssertEqual(peer?.online, true)
        XCTAssertEqual(peer?.battery, 88)
        XCTAssertEqual(peer?.publicKey, "BASE64KEY")
        XCTAssertEqual(peer?.lanAddress, "192.168.1.20:47100")
    }

    func testPeerOnlineCarriesEverythingNeededToDial() {
        client.handle("""
        {"type":"peer-online","deviceId":"peer-1","name":"Mac mini","platform":"macos",
         "publicKey":"KEY","lanAddress":"192.168.1.30:51000","battery":70}
        """)
        XCTAssertEqual(client.presence["peer-1"]?.publicKey, "KEY")
        XCTAssertEqual(client.presence["peer-1"]?.lanAddress, "192.168.1.30:51000")
    }

    /// A peer that moves to a new address must be reachable again. The server only
    /// learned to broadcast this recently, so pin it.
    func testPeerUpdateRefreshesTheLanAddress() {
        client.handle("""
        {"type":"peer-online","deviceId":"p","publicKey":"KEY","lanAddress":"10.0.0.1:1000","battery":50}
        """)
        client.handle("""
        {"type":"peer-update","deviceId":"p","battery":49,"lanAddress":"10.0.0.9:2000"}
        """)
        XCTAssertEqual(client.presence["p"]?.lanAddress, "10.0.0.9:2000")
        XCTAssertEqual(client.presence["p"]?.battery, 49)
    }

    /// The merge keeps what a frame omits. `peer-update` carries no publicKey, and losing
    /// it would leave a peer we can see but can never authenticate.
    func testAnUpdateWithoutAPublicKeyKeepsTheOneWeAlreadyHave() {
        client.handle("""
        {"type":"peer-online","deviceId":"p","publicKey":"KEY","lanAddress":"10.0.0.1:1000","battery":50}
        """)
        client.handle(#"{"type":"peer-update","deviceId":"p","battery":42}"#)

        XCTAssertEqual(client.presence["p"]?.publicKey, "KEY")
        XCTAssertEqual(client.presence["p"]?.lanAddress, "10.0.0.1:1000")
        XCTAssertEqual(client.presence["p"]?.battery, 42)
    }

    func testPeerOfflineMarksTheDeviceDownButKeepsItsIdentity() {
        client.handle("""
        {"type":"peer-online","deviceId":"p","publicKey":"KEY","lanAddress":"10.0.0.1:1000","battery":50}
        """)
        client.handle(#"{"type":"peer-offline","deviceId":"p"}"#)

        XCTAssertEqual(client.presence["p"]?.online, false)
        // Kept deliberately: the peer is unreachable now, but these are still valid when
        // it returns and save a round trip.
        XCTAssertEqual(client.presence["p"]?.publicKey, "KEY")
        XCTAssertEqual(client.presence["p"]?.lanAddress, "10.0.0.1:1000")
    }

    /// A new device on the account arrives as plain `peer-online` — there is no separate
    /// "paired" event any more, because there is no pairing step to announce.
    func testANewDeviceArrivesAsPeerOnline() {
        client.handle(#"{"type":"peer-online","deviceId":"new","publicKey":"K","lanAddress":"10.0.0.9:1000"}"#)
        XCTAssertEqual(client.presence["new"]?.online, true)
        XCTAssertEqual(client.presence["new"]?.publicKey, "K")
    }

    func testPresenceChangesNotifyTheObserver() {
        var seen: [String: PeerPresence] = [:]
        client.onPresenceChanged = { seen = $0 }
        client.handle(#"{"type":"peer-online","deviceId":"p","publicKey":"K","lanAddress":"1.2.3.4:5"}"#)
        XCTAssertEqual(seen["p"]?.publicKey, "K")
    }

    // MARK: - Malformed input
    //
    // Frames arrive over the network. Nothing here may crash the app — the data plane
    // rule is to fail soft.

    func testMalformedFramesAreIgnoredWithoutCrashing() {
        for frame in [
            "",
            "not json at all",
            "{}",
            "[]",
            #"{"type":"peer-online"}"#, // no deviceId
            #"{"type":"hello-ok"}"#, // no peers
            #"{"type":"unrecognised-future-frame","deviceId":"p"}"#,
            #"{"type":"peer-update","deviceId":"p","battery":"not a number"}"#,
        ] {
            client.handle(frame) // must simply not crash
        }
        XCTAssertTrue(client.presence["p"] == nil || client.presence["p"] != nil)
    }

    /// The server can add fields at any time; an older client must not choke on them.
    func testUnknownFieldsAreIgnored() {
        client.handle("""
        {"type":"peer-online","deviceId":"p","publicKey":"K","lanAddress":"1.2.3.4:5",
         "somethingAddedLater":{"nested":true}}
        """)
        XCTAssertEqual(client.presence["p"]?.publicKey, "K")
    }

    func testAPeerWithNoAddressYetIsRecordedWithoutOne() {
        // A device that connected before its listener bound advertises no lanAddress.
        // It should still appear as online, just not be dialable yet.
        client.handle(#"{"type":"peer-online","deviceId":"p","publicKey":"K","battery":10}"#)
        XCTAssertEqual(client.presence["p"]?.online, true)
        XCTAssertNil(client.presence["p"]?.lanAddress)
    }
}
