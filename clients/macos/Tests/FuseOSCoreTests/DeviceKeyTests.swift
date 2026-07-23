import CryptoKit
@testable import FuseOSCore
import Foundation
import XCTest

/// Parsing a peer's public key is the first thing done with bytes the control plane
/// relayed, and the result decides who we will do ECDH with. Everything malformed must
/// throw rather than crash or, worse, produce a usable-looking key.
///
/// These deliberately avoid `DeviceKey.privateKey()`: that reads and writes the real
/// login keychain under the app's own service name, and a test has no business mutating
/// the developer's keychain.
final class DeviceKeyTests: XCTestCase {

    private func validEncodedKey() -> String {
        P256.KeyAgreement.PrivateKey().publicKey.derRepresentation.base64EncodedString()
    }

    func testRoundTripsAValidKey() throws {
        let original = P256.KeyAgreement.PrivateKey().publicKey
        let encoded = original.derRepresentation.base64EncodedString()
        let decoded = try DeviceKey.decodePublic(base64: encoded)
        XCTAssertEqual(decoded.derRepresentation, original.derRepresentation)
    }

    /// The wire encoding is base64 SPKI DER, chosen because Android's
    /// `PublicKey.getEncoded()` emits exactly this. The prefix is the SPKI header for
    /// prime256v1 — if it ever changes, the two platforms have stopped agreeing.
    func testEncodingIsSpkiDerForP256() {
        let encoded = validEncodedKey()
        XCTAssertTrue(
            encoded.hasPrefix("MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE"),
            "expected a prime256v1 SPKI header, got \(encoded.prefix(40))",
        )
    }

    func testRejectsInputThatIsNotBase64() {
        XCTAssertThrowsError(try DeviceKey.decodePublic(base64: "!!! not base64 !!!"))
    }

    func testRejectsAnEmptyKey() {
        XCTAssertThrowsError(try DeviceKey.decodePublic(base64: ""))
    }

    func testRejectsWellFormedBase64ThatIsNotAKey() {
        XCTAssertThrowsError(
            try DeviceKey.decodePublic(base64: Data(repeating: 0xAB, count: 91).base64EncodedString()),
        )
    }

    /// The old placeholder was 32 random bytes presented as a public key. A device still
    /// running that build must be refused, not treated as a peer.
    func testRejectsTheLegacyRandomBytesPlaceholder() {
        let legacy = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        XCTAssertThrowsError(try DeviceKey.decodePublic(base64: legacy))
    }

    /// A key on a different curve must not be silently accepted onto a P-256 exchange.
    func testRejectsAKeyFromTheWrongCurve() {
        let p384 = P384.KeyAgreement.PrivateKey().publicKey.derRepresentation.base64EncodedString()
        XCTAssertThrowsError(try DeviceKey.decodePublic(base64: p384))
    }

    func testRejectsATruncatedKey() {
        let full = Data(base64Encoded: validEncodedKey())!
        let truncated = full.prefix(full.count / 2).base64EncodedString()
        XCTAssertThrowsError(try DeviceKey.decodePublic(base64: truncated))
    }

    /// A flipped byte lands off the curve. Rejecting it is what stops a corrupted or
    /// tampered peer card from reaching the key agreement.
    func testRejectsAKeyWithACorruptedPoint() {
        var bytes = Data(base64Encoded: validEncodedKey())!
        bytes[bytes.count - 1] ^= 0xFF
        XCTAssertThrowsError(try DeviceKey.decodePublic(base64: bytes.base64EncodedString()))
    }

    func testTwoDevicesNeverGenerateTheSameKey() {
        XCTAssertNotEqual(validEncodedKey(), validEncodedKey())
    }
}
