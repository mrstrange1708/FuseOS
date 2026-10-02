import CryptoKit
@testable import FuseOSCore
import XCTest

/// The same channel — handshake, keys, sealed frames — over the relay's message pieces.
final class RelayWireTests: XCTestCase {
    /// Two wires joined as the server joins them: one's pieces are the other's input.
    private func relayPair() -> (RelayWire, RelayWire) {
        final class Box: @unchecked Sendable { var a: RelayWire?; var b: RelayWire? }
        let box = Box()
        let a = RelayWire(peerId: "bbbb", stream: "s") { data, close in
            if close { box.b?.end() } else if let data { box.b?.deliver(data) }
            return true
        }
        let b = RelayWire(peerId: "aaaa", stream: "s") { data, close in
            if close { box.a?.end() } else if let data { box.a?.deliver(data) }
            return true
        }
        box.a = a
        box.b = b
        return (a, b)
    }

    func testASealedChannelRunsOverRelayPiecesWithBigFramesSplitAndRejoined() async throws {
        let ka = P256.KeyAgreement.PrivateKey(), kb = P256.KeyAgreement.PrivateKey()
        let (wa, wb) = relayPair()
        async let dialed = LanChannel.handshake(
            connection: wa, selfDeviceId: "aaaa", privateKey: ka, trustedKeyFor: { _ in kb.publicKey },
        )
        async let accepted = LanChannel.handshake(
            connection: wb, selfDeviceId: "bbbb", privateKey: kb, trustedKeyFor: { _ in ka.publicKey },
        )
        let (alice, bob) = try await (dialed, accepted)
        XCTAssertTrue(alice.viaRelay && bob.viaRelay)

        var clip = FuseEnvelope()
        clip.clipText = FuseClipText.with { $0.text = "over the relay" }
        try await alice.send(clip)
        let got = try await bob.receive()
        XCTAssertEqual(got.clipText.text, "over the relay")

        // Bigger than one 64 KB relay piece: split on the way, whole on arrival.
        let big = Data((0 ..< 200 * 1024).map { UInt8(truncatingIfNeeded: $0) })
        var chunk = FuseEnvelope()
        chunk.fileChunk = FuseFileChunk.with { $0.data = big }
        try await bob.send(chunk)
        let back = try await alice.receive()
        XCTAssertEqual(back.fileChunk.data, big)

        alice.close()
        do {
            _ = try await bob.receive()
            XCTFail("the close should reach the other end")
        } catch {}
    }

    func testTheRelayCarriesCopiesAndCommandsNotFilesMirroringOrHistory() {
        var clip = FuseEnvelope()
        clip.clipText = FuseClipText.with { $0.text = "hi" }
        XCTAssertTrue(Relay.carries(clip))
        var file = FuseEnvelope()
        file.fileChunk = FuseFileChunk()
        XCTAssertFalse(Relay.carries(file))
        var frame = FuseEnvelope()
        frame.screenFrame = FuseScreenFrame()
        XCTAssertFalse(Relay.carries(frame))
        var history = FuseEnvelope()
        history.historySync = FuseHistorySync()
        XCTAssertFalse(Relay.carries(history))
    }
}
