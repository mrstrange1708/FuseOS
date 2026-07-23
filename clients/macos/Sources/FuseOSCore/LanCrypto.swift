import CryptoKit
import Foundation

/// Channel crypto for the LAN data plane. The Android `LanCrypto` is the mirror of this
/// file; the two must derive identical keys or no device can talk to the other.
///
/// Both ends already hold the other's P-256 public key, vouched for by the control plane
/// at pairing time. ECDH over those static keys yields a shared secret, and the two fresh
/// per-connection nonces exchanged in the handshake salt it into session keys — one per
/// direction, so the GCM counters on the two sides can never collide.
///
/// ponytail: static-static ECDH has no forward secrecy — a stolen device key decrypts any
/// recorded session. The upgrade is ephemeral keys plus signatures (Noise IK), skipped
/// because it costs a full handshake protocol to defend against an attacker who already
/// has the device.
enum LanCrypto {
    static let nonceLength = 32

    private static let infoLowToHigh = Data("fuseos:lan:v1:low-to-high".utf8)
    private static let infoHighToLow = Data("fuseos:lan:v1:high-to-low".utf8)

    /// The two directional keys for a connection, from this device's point of view.
    struct SessionKeys {
        let send: SymmetricKey
        let receive: SymmetricKey
    }

    /// Derives this connection's keys.
    ///
    /// Ordering is by device id rather than by who dialed, so both ends independently
    /// agree on which nonce comes first and which key is theirs without exchanging
    /// anything more.
    static func sessionKeys(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: P256.KeyAgreement.PublicKey,
        selfDeviceId: String,
        peerDeviceId: String,
        selfNonce: Data,
        peerNonce: Data,
    ) throws -> SessionKeys {
        let selfIsLow = selfDeviceId < peerDeviceId
        let salt = selfIsLow ? selfNonce + peerNonce : peerNonce + selfNonce
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

        let lowToHigh = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: infoLowToHigh, outputByteCount: 32,
        )
        let highToLow = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: infoHighToLow, outputByteCount: 32,
        )
        return selfIsLow
            ? SessionKeys(send: lowToHigh, receive: highToLow)
            : SessionKeys(send: highToLow, receive: lowToHigh)
    }

    static func seal(key: SymmetricKey, counter: UInt64, plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: gcmNonce(counter))
        // Java's Cipher returns ciphertext||tag from one call; match that layout.
        return box.ciphertext + box.tag
    }

    /// Throws if the frame was tampered with or arrived out of order.
    static func open(key: SymmetricKey, counter: UInt64, ciphertext: Data) throws -> Data {
        let tagLength = 16
        guard ciphertext.count >= tagLength else { throw Failure.shortFrame }
        let split = ciphertext.count - tagLength
        let box = try AES.GCM.SealedBox(
            nonce: gcmNonce(counter),
            ciphertext: ciphertext.prefix(split),
            tag: ciphertext.suffix(tagLength),
        )
        return try AES.GCM.open(box, using: key)
    }

    static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    enum Failure: Error { case shortFrame }

    /// 12-byte GCM nonce: a big-endian frame counter in the low 8 bytes. Safe to start at
    /// zero because the keys are fresh per connection.
    private static func gcmNonce(_ counter: UInt64) -> AES.GCM.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0 ..< 8 {
            bytes[11 - i] = UInt8((counter >> (8 * UInt64(i))) & 0xFF)
        }
        // Fixed 12-byte length, so this cannot fail.
        return try! AES.GCM.Nonce(data: Data(bytes))
    }
}
