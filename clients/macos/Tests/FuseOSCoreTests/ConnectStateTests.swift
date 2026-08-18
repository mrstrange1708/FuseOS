import XCTest
@testable import FuseOSCore

/// The connect screen is the one place a user is told *why* two devices aren't talking,
/// so the stage each situation maps to is behaviour, not presentation.
final class ConnectStateTests: XCTestCase {
    private func presence(online: Bool, lan: String?) -> PeerPresence {
        PeerPresence(online: online, battery: nil, publicKey: nil, lanAddress: lan)
    }

    private func evaluate(
        selfLan: String?,
        peers: [String: PeerPresence],
        connected: Set<String> = [],
    ) -> ConnectState {
        ConnectStateEvaluator.evaluate(
            selfLanAddress: selfLan,
            peerIds: Array(peers.keys).sorted(),
            presence: peers,
            connected: connected,
        )
    }

    func testNoPairedDevicesIsNotPaired() {
        XCTAssertEqual(evaluate(selfLan: "192.168.1.5:9000", peers: [:]).stage, .notPaired)
    }

    func testPairedButOfflinePeer() {
        let state = evaluate(selfLan: "192.168.1.5:9000", peers: ["b": presence(online: false, lan: nil)])
        XCTAssertEqual(state.stage, .peerOffline)
        XCTAssertEqual(state.peerId, "b")
    }

    func testOnlinePeerOnAnotherSubnetReportsBothNetworks() {
        let state = evaluate(
            selfLan: "192.168.1.5:9000",
            peers: ["b": presence(online: true, lan: "10.171.188.173:41234")],
        )
        XCTAssertEqual(state.stage, .differentNetwork)
        XCTAssertEqual(state.selfSubnet, "192.168.1")
        XCTAssertEqual(state.peerSubnet, "10.171.188")
    }

    func testSameSubnetWithoutChannelIsConnecting() {
        let state = evaluate(
            selfLan: "192.168.43.24:9000",
            peers: ["b": presence(online: true, lan: "192.168.43.1:41234")],
        )
        XCTAssertEqual(state.stage, .connecting)
    }

    /// A listener that hasn't bound yet is a normal launch race, not a wrong-network error.
    func testMissingLanAddressIsConnectingNotDifferentNetwork() {
        let state = evaluate(selfLan: nil, peers: ["b": presence(online: true, lan: nil)])
        XCTAssertEqual(state.stage, .connecting)
    }

    /// The channel is ground truth: presence may be stale or absent, but if bytes flow, we
    /// are connected. Continue must never be withheld from a peer we can actually reach.
    func testLiveChannelOutranksStalePresence() {
        let state = evaluate(
            selfLan: "192.168.1.5:9000",
            peers: ["b": presence(online: false, lan: nil)],
            connected: ["b"],
        )
        XCTAssertEqual(state.stage, .connected)
        XCTAssertEqual(state.peerId, "b")
    }

    /// With several paired devices the screen follows the furthest-along one, so one
    /// offline laptop cannot mask a phone that is ready to use.
    func testFurthestAlongPeerWins() {
        let state = evaluate(
            selfLan: "192.168.1.5:9000",
            peers: [
                "a": presence(online: false, lan: nil),
                "z": presence(online: true, lan: "192.168.1.9:41234"),
            ],
            connected: ["z"],
        )
        XCTAssertEqual(state.stage, .connected)
        XCTAssertEqual(state.peerId, "z")
    }

    func testSubnetParsingRejectsNonDottedQuads() {
        XCTAssertEqual(ConnectStateEvaluator.subnet(of: "192.168.1.5:9000"), "192.168.1")
        XCTAssertNil(ConnectStateEvaluator.subnet(of: "fe80::1:9000"))
        XCTAssertNil(ConnectStateEvaluator.subnet(of: "999.1.1.1:9000"))
        XCTAssertNil(ConnectStateEvaluator.subnet(of: "hostname:9000"))
    }
}
