import CryptoKit
@testable import FuseOSCore
import XCTest

/// Channel crypto. If any of this drifts from Android's `LanCrypto`, no two devices can
/// talk — and the symptom is a silent failure to connect, not an exception anyone sees.
final class LanCryptoTests: XCTestCase {

    private func keyPair() -> P256.KeyAgreement.PrivateKey { P256.KeyAgreement.PrivateKey() }

    private func nonce(_ byte: UInt8) -> Data { Data(repeating: byte, count: LanCrypto.nonceLength) }

    /// The property everything else depends on: what A encrypts, B can decrypt. A's send
    /// key must be B's receive key and vice versa.
    func testBothSidesDeriveTheMatchingKeyPair() throws {
        let a = keyPair(), b = keyPair()
        let nonceA = nonce(1), nonceB = nonce(2)

        let keysA = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonceA, peerNonce: nonceB,
        )
        let keysB = try LanCrypto.sessionKeys(
            privateKey: b, peerPublicKey: a.publicKey,
            selfDeviceId: "bbbb", peerDeviceId: "aaaa",
            selfNonce: nonceB, peerNonce: nonceA,
        )

        XCTAssertEqual(keysA.send, keysB.receive)
        XCTAssertEqual(keysA.receive, keysB.send)
    }

    /// Separate keys per direction is what lets both sides start their GCM counter at
    /// zero without ever reusing a nonce.
    func testTheTwoDirectionsUseDifferentKeys() throws {
        let a = keyPair(), b = keyPair()
        let keys = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonce(1), peerNonce: nonce(2),
        )
        XCTAssertNotEqual(keys.send, keys.receive)
    }

    /// Ordering is by device id, never by who dialled. The lower id always owns the
    /// "low-to-high" key, so the two ends agree without negotiating anything.
    func testKeyRolesFollowDeviceIdOrderNotDialDirection() throws {
        let a = keyPair(), b = keyPair()
        let nonceA = nonce(1), nonceB = nonce(2)

        let lower = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonceA, peerNonce: nonceB,
        )
        let higher = try LanCrypto.sessionKeys(
            privateKey: b, peerPublicKey: a.publicKey,
            selfDeviceId: "bbbb", peerDeviceId: "aaaa",
            selfNonce: nonceB, peerNonce: nonceA,
        )
        // The lower id sends on low-to-high; the higher id receives on it.
        XCTAssertEqual(lower.send, higher.receive)
    }

    /// Fresh nonces per connection are what make the session keys per-session. Without
    /// this, every connection between the same two devices would reuse one key stream.
    func testDifferentNoncesProduceDifferentSessionKeys() throws {
        let a = keyPair(), b = keyPair()
        let first = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonce(1), peerNonce: nonce(2),
        )
        let second = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonce(3), peerNonce: nonce(4),
        )
        XCTAssertNotEqual(first.send, second.send)
    }

    func testAThirdPartyKeyDerivesSomethingUnusable() throws {
        let a = keyPair(), b = keyPair(), impostor = keyPair()
        let real = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: b.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonce(1), peerNonce: nonce(2),
        )
        let fake = try LanCrypto.sessionKeys(
            privateKey: a, peerPublicKey: impostor.publicKey,
            selfDeviceId: "aaaa", peerDeviceId: "bbbb",
            selfNonce: nonce(1), peerNonce: nonce(2),
        )
        XCTAssertNotEqual(real.send, fake.send)
    }

    // MARK: - Frame sealing

    private var key: SymmetricKey { SymmetricKey(data: Data(repeating: 7, count: 32)) }

    func testSealAndOpenRoundTrip() throws {
        let plaintext = Data("clipboard contents".utf8)
        let sealed = try LanCrypto.seal(key: key, counter: 0, plaintext: plaintext)
        XCTAssertEqual(try LanCrypto.open(key: key, counter: 0, ciphertext: sealed), plaintext)
    }

    /// The counter IS the nonce, so opening at the wrong counter must fail. This is what
    /// makes a replayed or reordered frame fail loudly instead of being applied.
    func testOpeningAtTheWrongCounterFails() throws {
        let sealed = try LanCrypto.seal(key: key, counter: 7, plaintext: Data("x".utf8))
        XCTAssertThrowsError(try LanCrypto.open(key: key, counter: 8, ciphertext: sealed))
        XCTAssertThrowsError(try LanCrypto.open(key: key, counter: 6, ciphertext: sealed))
    }

    func testOpeningWithTheWrongKeyFails() throws {
        let sealed = try LanCrypto.seal(key: key, counter: 0, plaintext: Data("x".utf8))
        let wrong = SymmetricKey(data: Data(repeating: 8, count: 32))
        XCTAssertThrowsError(try LanCrypto.open(key: wrong, counter: 0, ciphertext: sealed))
    }

    func testATamperedFrameFailsItsTagCheck() throws {
        var sealed = try LanCrypto.seal(key: key, counter: 0, plaintext: Data("payload".utf8))
        // Index from startIndex, not 0: `seal` concatenates, and the resulting Data is a
        // slice whose startIndex is non-zero. Subscripting with a literal 0 traps.
        sealed[sealed.startIndex] ^= 0xFF
        XCTAssertThrowsError(try LanCrypto.open(key: key, counter: 0, ciphertext: sealed))
    }

    /// The frames handed to `open` come off the network as slices at arbitrary offsets,
    /// not tidy zero-based buffers. Anything indexing them by absolute position breaks
    /// only in production, so pin the slice case explicitly.
    func testOpenHandlesADataSliceWithANonZeroStartIndex() throws {
        let plaintext = Data("offset payload".utf8)
        let sealed = try LanCrypto.seal(key: key, counter: 5, plaintext: plaintext)
        let padded = Data(repeating: 0xEE, count: 7) + sealed
        let slice = padded.dropFirst(7)
        XCTAssertNotEqual(slice.startIndex, 0, "precondition: this must be an offset slice")
        XCTAssertEqual(try LanCrypto.open(key: key, counter: 5, ciphertext: slice), plaintext)
    }

    func testATruncatedFrameIsRejectedRatherThanCrashing() {
        XCTAssertThrowsError(try LanCrypto.open(key: key, counter: 0, ciphertext: Data([1, 2, 3])))
        XCTAssertThrowsError(try LanCrypto.open(key: key, counter: 0, ciphertext: Data()))
    }

    func testSameCounterAndKeyProducesDistinctCiphertextPerPlaintext() throws {
        let one = try LanCrypto.seal(key: key, counter: 0, plaintext: Data("aaa".utf8))
        let two = try LanCrypto.seal(key: key, counter: 0, plaintext: Data("bbb".utf8))
        XCTAssertNotEqual(one, two)
    }

    func testSealingIsDeterministicForAFixedKeyCounterAndPlaintext() throws {
        // AES-GCM with an explicit nonce has no randomness, which is what lets the peer
        // decrypt without transmitting a per-frame nonce.
        let one = try LanCrypto.seal(key: key, counter: 3, plaintext: Data("same".utf8))
        let two = try LanCrypto.seal(key: key, counter: 3, plaintext: Data("same".utf8))
        XCTAssertEqual(one, two)
    }

    func testALargePayloadRoundTrips() throws {
        // Images ride inline up to 3 MB, so the crypto has to handle that size.
        let big = Data(repeating: 0xAB, count: 3 * 1024 * 1024)
        let sealed = try LanCrypto.seal(key: key, counter: 1, plaintext: big)
        XCTAssertEqual(try LanCrypto.open(key: key, counter: 1, ciphertext: sealed), big)
    }

    func testCiphertextCarriesTheSixteenByteTag() throws {
        // Java's Cipher returns ciphertext||tag from one call; the layouts must match or
        // neither side can open the other's frames.
        let plaintext = Data("1234567890".utf8)
        let sealed = try LanCrypto.seal(key: key, counter: 0, plaintext: plaintext)
        XCTAssertEqual(sealed.count, plaintext.count + 16)
    }

    /// Frozen cross-platform vector.
    ///
    /// This exact byte string was produced independently by `javax.crypto` using the same
    /// algorithm Android's `LanCrypto.seal` runs, then confirmed to match CryptoKit's
    /// output — so it pins real interoperability rather than merely recording what this
    /// platform happens to emit. A change to the GCM nonce layout or the ciphertext||tag
    /// ordering on either side breaks this test instead of silently breaking every
    /// connection between a phone and a Mac.
    ///
    /// Android has the mirror of this in `LanCryptoTest`. If one moves, both move.
    func testFrozenWireVectorForCrossPlatformAgreement() throws {
        let fixedKey = SymmetricKey(data: Data((0 ..< 32).map { UInt8($0) }))
        let sealed = try LanCrypto.seal(
            key: fixedKey, counter: 42, plaintext: Data("FuseOS".utf8),
        )
        XCTAssertEqual(sealed.base64EncodedString(), "frCUEgIbmNFqEt4oF3ElnFFfJ5Eo4w==")
        XCTAssertEqual(
            sealed.map { String(format: "%02x", $0) }.joined(),
            "7eb09412021b98d16a12de281771259c515f279128e3",
        )
    }

    /// The counter's big-endian placement in the GCM nonce is part of the wire contract:
    /// both sides must land on the same nonce for the same frame number or nothing opens.
    func testCounterPlacementIsPinnedAcrossCounters() throws {
        let fixedKey = SymmetricKey(data: Data((0 ..< 32).map { UInt8($0) }))
        let plaintext = Data("x".utf8)
        // Counter 0 and counter 256 differ only in a byte the layout decides.
        let zero = try LanCrypto.seal(key: fixedKey, counter: 0, plaintext: plaintext)
        let two56 = try LanCrypto.seal(key: fixedKey, counter: 256, plaintext: plaintext)
        XCTAssertNotEqual(zero, two56)
        XCTAssertEqual(zero.base64EncodedString(), "dv/LwO+2C2v4zAEKLFJzzIY=")
        XCTAssertEqual(two56.base64EncodedString(), "WOApDXtgqqzGZ4UNR6CYTRw=")
    }
}
