import CryptoKit
@testable import FuseOSCore
import Foundation
import XCTest

/// Byte-exact wire vectors, pinned identically in Android's `WireFormatTest.kt`.
///
/// This is the only thing standing between "both clients still work" and "one of them
/// changed and nobody noticed until two real devices refused to talk". Everything below
/// is derived from fixed keypairs and fixed nonces, so it is reproducible in any language
/// on any machine — and every constant here was confirmed to match the Kotlin side.
///
/// **If one of these fails, the question is never "what is the new expected value".** It
/// is "what changed, and has the other client changed with it". A deliberate wire change
/// moves both files in the same commit.
final class WireFormatTests: XCTestCase {

    // Device A holds the lexicographically LOW id, so it dials and its send key is
    // `fuseos:lan:v1:low-to-high`.
    private static let idA = "aaaa-1111"
    private static let idB = "bbbb-2222"

    private static let privateA = """
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgKFgjbMoidvK8KHevSQsBRwvDZNIs\
    3IZY7xhH6E8P0N+hRANCAASEy/cxOIAEHvclBeTSksCGbG/DviZPFpKLTZ5slYAwzbc8hYRJPJ6U\
    /gu+Q8H7LBIerxWRNfgbxSlhE2kBFvgy
    """
    private static let publicA = """
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEhMv3MTiABB73JQXk0pLAhmxvw74mTxaSi02ebJWA\
    MM23PIWESTyelP4LvkPB+ywSHq8VkTX4G8UpYRNpARb4Mg==
    """
    private static let privateB = """
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgPu++Z0YtKFYz9bdlGPEUxzVFi6hL\
    4ZISuravkAM7KXuhRANCAAT/uEjYAhOmg0CJ8MSuO4OZy7irsucZ+advc26dZfmLkppz5YkMrCKq\
    vtSGKWMR5XlpuXVpQi67Z8SBWc22x8TP
    """
    private static let publicB = """
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE/7hI2AITpoNAifDErjuDmcu4q7LnGfmnb3NunWX5\
    i5Kac+WJDKwiqr7UhiljEeV5abl1aUIuu2fEgVnNtsfEzw==
    """

    private static let nonceAHex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    private static let nonceBHex = "fffefdfcfbfaf9f8f7f6f5f4f3f2f1f0efeeedecebeae9e8e7e6e5e4e3e2e1e0"

    /// `Envelope{ source="aaaa-1111", seq=7, sent_at=1700000000000, ClipText("hello") }`
    private static let envelopeHex = "0a09616161612d3131313110071880d095ffbc3152070a0568656c6c6f"

    private static let keyLowToHighHex =
        "cf74a94a7866a9789b1ab5e8c82a91c0883db5cebd5bb4e01231624bbc9e9328"
    private static let keyHighToLowHex =
        "fb90c855dc3eee0c98b8c2ba8d2a6e8b237d6b4b7e5eaebdf1d8b6c7e782b925"

    /// `seal(key = 0x00…0x1f, counter = 0, plaintext = envelope)`.
    private static let sealedFixedKeyHex =
        "04b5d4bfd44dae8c399998251f34114947bcea627a866a2ae8fbdfefaadd2c012ffb3acccd9c22e364a4cc4561"

    /// The complete frame A puts on the wire: `[4-byte BE length][ciphertext||tag]`,
    /// sealed under the low-to-high key at counter 0.
    private static let frameAFirstHex =
        "0000002df7f176472e1c4f2bc82370cdbbdca5a0d33887b889c1ec6ece0299f28440d9373cf0b89c549e0ccbe36a7afc78"

    // MARK: - Helpers

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    private func unhex(_ string: String) -> Data {
        var data = Data()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            data.append(UInt8(string[index ..< next], radix: 16)!)
            index = next
        }
        return data
    }

    private func privateKey(_ base64: String) throws -> P256.KeyAgreement.PrivateKey {
        try P256.KeyAgreement.PrivateKey(derRepresentation: Data(base64Encoded: base64)!)
    }

    // MARK: - Keys

    /// The keypairs must decode, and their public halves must serialise to exactly the
    /// SPKI DER Android pinned — that shared encoding is what lets a peer key cross.
    func testFixedKeypairsAgreeOnTheirPublicEncoding() throws {
        let a = try privateKey(Self.privateA), b = try privateKey(Self.privateB)
        XCTAssertEqual(a.publicKey.derRepresentation.base64EncodedString(), Self.publicA)
        XCTAssertEqual(b.publicKey.derRepresentation.base64EncodedString(), Self.publicB)
    }

    /// The session keys are the heart of it: if these two hex strings ever differ between
    /// the platforms, every connection between a phone and a Mac fails silently.
    func testSessionKeysMatchTheKotlinVectors() throws {
        let a = try privateKey(Self.privateA), b = try privateKey(Self.privateB)
        let keys = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: Self.idA, peerDeviceId: Self.idB,
            selfNonce: unhex(Self.nonceAHex), peerNonce: unhex(Self.nonceBHex),
        )
        XCTAssertEqual(keys.send.withUnsafeBytes { hex(Data($0)) }, Self.keyLowToHighHex)
        XCTAssertEqual(keys.receive.withUnsafeBytes { hex(Data($0)) }, Self.keyHighToLowHex)
    }

    /// …and from B's side the two are crossed, which is what makes the channel work.
    func testTheHighDeviceDerivesTheKeysCrossed() throws {
        let a = try privateKey(Self.privateA), b = try privateKey(Self.privateB)
        let keys = try LanCrypto.sessionKeys(
            privateKey: b, peerPublicKey: a.publicKey,
            selfDeviceId: Self.idB, peerDeviceId: Self.idA,
            selfNonce: unhex(Self.nonceBHex), peerNonce: unhex(Self.nonceAHex),
        )
        XCTAssertEqual(keys.send.withUnsafeBytes { hex(Data($0)) }, Self.keyHighToLowHex)
        XCTAssertEqual(keys.receive.withUnsafeBytes { hex(Data($0)) }, Self.keyLowToHighHex)
    }

    // MARK: - Framing

    func testHandshakeByteLayout() {
        // [2-byte BE id length]["aaaa-1111"][32-byte nonce]
        var length = UInt16(Self.idA.utf8.count).bigEndian
        let frame = Data(bytes: &length, count: 2) + Data(Self.idA.utf8) + unhex(Self.nonceAHex)
        XCTAssertEqual(hex(frame), "0009616161612d31313131" + Self.nonceAHex)
        XCTAssertEqual(frame.count, 43)
    }

    /// The protobuf encoding is part of the contract too — a renumbered field would
    /// change these bytes while both clients still compiled.
    func testEnvelopeSerialisesToThePinnedBytes() throws {
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = Self.idA
        envelope.seq = 7
        envelope.sentAtUnixMs = 1_700_000_000_000
        envelope.clipText = FuseClipText.with { $0.text = "hello" }
        XCTAssertEqual(hex(try envelope.serializedData()), Self.envelopeHex)
    }

    func testSealingUnderTheFixedKeyMatchesKotlin() throws {
        let key = SymmetricKey(data: Data((0 ..< 32).map { UInt8($0) }))
        let sealed = try LanCrypto.seal(key: key, counter: 0, plaintext: unhex(Self.envelopeHex))
        XCTAssertEqual(hex(sealed), Self.sealedFixedKeyHex)
    }

    /// The whole stack end to end: ECDH → HKDF → AES-GCM → length prefix. This is the
    /// exact byte sequence an Android phone puts on the wire for its first frame.
    func testTheCompleteFirstFrameMatchesKotlin() throws {
        let a = try privateKey(Self.privateA), b = try privateKey(Self.privateB)
        let keys = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: Self.idA, peerDeviceId: Self.idB,
            selfNonce: unhex(Self.nonceAHex), peerNonce: unhex(Self.nonceBHex),
        )
        let body = try LanCrypto.seal(key: keys.send, counter: 0, plaintext: unhex(Self.envelopeHex))
        var length = UInt32(body.count).bigEndian
        XCTAssertEqual(hex(Data(bytes: &length, count: 4) + body), Self.frameAFirstHex)
    }

    /// And the Mac can open what the phone sealed — the property all of the above exists
    /// to protect, asserted directly.
    func testAFrameSealedWithKotlinsVectorOpensOnThisPlatform() throws {
        let a = try privateKey(Self.privateA), b = try privateKey(Self.privateB)
        // B is the receiving side; its receive key is A's send key.
        let keysB = try LanCrypto.sessionKeys(
            privateKey: b, peerPublicKey: a.publicKey,
            selfDeviceId: Self.idB, peerDeviceId: Self.idA,
            selfNonce: unhex(Self.nonceBHex), peerNonce: unhex(Self.nonceAHex),
        )
        let frame = unhex(Self.frameAFirstHex).dropFirst(4) // strip the length prefix
        let plaintext = try LanCrypto.open(key: keysB.receive, counter: 0, ciphertext: frame)

        let envelope = try FuseEnvelope(serializedBytes: plaintext)
        XCTAssertEqual(envelope.sourceDeviceID, Self.idA)
        XCTAssertEqual(envelope.seq, 7)
        XCTAssertEqual(envelope.clipText.text, "hello")
    }
}
