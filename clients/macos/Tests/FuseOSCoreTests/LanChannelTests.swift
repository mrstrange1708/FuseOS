import CryptoKit
@testable import FuseOSCore
import Foundation
import Network
import XCTest

/// The framing and handshake that two physical devices depend on.
///
/// Android's `LanChannelTest` is the mirror of this file. The wire format is the contract
/// between them, so where a value is pinned here it is pinned there too.
final class LanChannelTests: XCTestCase {

    // MARK: - Length prefixes

    /// These parse attacker-controlled bytes before anything is authenticated, and they
    /// replaced a `load(as:)` that required an alignment the network stack does not
    /// guarantee. Exercise the boundaries and, critically, offset slices.
    func testBigEndianLengthDecoding() {
        XCTAssertEqual(Data([0x00, 0x00, 0x00, 0x00]).beUInt32, 0)
        XCTAssertEqual(Data([0x00, 0x00, 0x00, 0x01]).beUInt32, 1)
        XCTAssertEqual(Data([0x00, 0x00, 0x01, 0x00]).beUInt32, 256)
        XCTAssertEqual(Data([0xFF, 0xFF, 0xFF, 0xFF]).beUInt32, UInt32.max)
        XCTAssertEqual(Data([0x00, 0x40, 0x00, 0x00]).beUInt32, 4 * 1024 * 1024)

        XCTAssertEqual(Data([0x00, 0x00]).beUInt16, 0)
        XCTAssertEqual(Data([0x01, 0x00]).beUInt16, 256)
        XCTAssertEqual(Data([0xFF, 0xFF]).beUInt16, UInt16.max)
    }

    /// The exact case that motivated hand-assembling the bytes: a length prefix arriving
    /// as a slice at a non-zero, unaligned offset.
    func testLengthDecodingWorksOnAnUnalignedSlice() {
        let backing = Data([0xEE, 0xEE, 0xEE, 0x00, 0x00, 0x01, 0x00])
        let slice = backing.dropFirst(3)
        XCTAssertNotEqual(slice.startIndex, 0, "precondition: must be an offset slice")
        XCTAssertEqual(slice.beUInt32, 256)
    }

    /// Big-endian is the contract; a little-endian read would decode this as a huge
    /// number and trip the frame cap instead of reading a 1-byte frame.
    func testByteOrderIsBigEndianNotHostOrder() {
        XCTAssertEqual(Data([0x00, 0x00, 0x00, 0x01]).beUInt32, 1)
        XCTAssertNotEqual(Data([0x01, 0x00, 0x00, 0x00]).beUInt32, 1)
    }

    // MARK: - Handshake over a real loopback connection

    /// Brings up a listener and dials it, then runs the real handshake on both ends
    /// concurrently — both sides write before reading, so they must overlap.
    private func connectedPair(
        selfId: String,
        peerId: String,
        selfKey: P256.KeyAgreement.PrivateKey,
        peerKey: P256.KeyAgreement.PrivateKey,
        listenerTrusts: @escaping @Sendable (String) -> P256.KeyAgreement.PublicKey?,
        dialerTrusts: @escaping @Sendable (String) -> P256.KeyAgreement.PublicKey?,
    ) async throws -> (LanChannel, LanChannel) {
        let listener = try NWListener(using: .tcp)
        let inbound = Task { () -> NWConnection in
            try await withCheckedThrowingContinuation { continuation in
                listener.newConnectionHandler = { connection in
                    listener.newConnectionHandler = nil
                    continuation.resume(returning: connection)
                }
                listener.start(queue: .global())
            }
        }
        // Wait for the port to be assigned.
        while listener.port == nil || listener.port?.rawValue == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let port = listener.port!
        defer { listener.cancel() }

        let dialConnection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        dialConnection.start(queue: .global())
        try await dialConnection.waitUntilReady()

        let acceptConnection = try await inbound.value
        acceptConnection.start(queue: .global())
        try await acceptConnection.waitUntilReady()

        async let dialed = LanChannel.handshake(
            connection: dialConnection, selfDeviceId: selfId,
            privateKey: selfKey, trustedKeyFor: dialerTrusts,
        )
        async let accepted = LanChannel.handshake(
            connection: acceptConnection, selfDeviceId: peerId,
            privateKey: peerKey, trustedKeyFor: listenerTrusts,
        )
        return try await (dialed, accepted)
    }

    private func clip(_ text: String) -> FuseEnvelope {
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = "sender"
        envelope.seq = 1
        envelope.clipText = FuseClipText.with { $0.text = text }
        return envelope
    }

    func testPairedDevicesExchangeEnvelopesInBothDirections() async throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        let (alice, bob) = try await connectedPair(
            selfId: "aaaa-1111", peerId: "bbbb-2222", selfKey: a, peerKey: b,
            listenerTrusts: { _ in a.publicKey }, dialerTrusts: { _ in b.publicKey },
        )
        defer { alice.close(); bob.close() }

        XCTAssertEqual(alice.peerDeviceId, "bbbb-2222")
        XCTAssertEqual(bob.peerDeviceId, "aaaa-1111")

        try await alice.send(clip("copied on A"))
        let gotOnB = try await bob.receive()
        XCTAssertEqual(gotOnB.clipText.text, "copied on A")

        try await bob.send(clip("copied on B"))
        let gotOnA = try await alice.receive()
        XCTAssertEqual(gotOnA.clipText.text, "copied on B")

        // Several frames in a row: the GCM counters only stay aligned if both sides
        // advance in lockstep, so drift shows up here and nowhere else.
        for i in 0 ..< 5 { try await alice.send(clip("frame \(i)")) }
        for i in 0 ..< 5 {
            let received = try await bob.receive()
            XCTAssertEqual(received.clipText.text, "frame \(i)")
        }
    }

    func testAPeerWeHoldNoKeyForIsRejectedBeforeAnyPayload() async throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        do {
            // B is paired with A, but A has never heard of B.
            let (alice, bob) = try await connectedPair(
                selfId: "aaaa-1111", peerId: "bbbb-2222", selfKey: a, peerKey: b,
                listenerTrusts: { _ in a.publicKey }, dialerTrusts: { _ in nil },
            )
            alice.close()
            bob.close()
            XCTFail("handshake should have refused a peer with no trusted key")
        } catch let error as LanChannel.Failure {
            guard case .untrustedPeer = error else {
                return XCTFail("expected untrustedPeer, got \(error)")
            }
        }
    }

    /// A ~1 MB payload exercises the multi-read path that small frames never touch —
    /// an image sync is exactly this shape.
    func testALargePayloadRoundTrips() async throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        let (alice, bob) = try await connectedPair(
            selfId: "aaaa-1111", peerId: "bbbb-2222", selfKey: a, peerKey: b,
            listenerTrusts: { _ in a.publicKey }, dialerTrusts: { _ in b.publicKey },
        )
        defer { alice.close(); bob.close() }

        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = "sender"
        envelope.seq = 1
        envelope.clipImage = FuseClipImage.with {
            $0.mime = "image/png"
            $0.data = Data(repeating: 0xAB, count: 1024 * 1024)
        }
        try await alice.send(envelope)

        let received = try await bob.receive()
        XCTAssertEqual(received.clipImage.data.count, 1024 * 1024)
        XCTAssertEqual(received.clipImage.mime, "image/png")
    }
}
