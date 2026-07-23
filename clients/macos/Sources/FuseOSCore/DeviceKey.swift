import CryptoKit
import Foundation

/// This device's long-lived P-256 identity.
///
/// The public key is registered as `devices.public_key`, reaches peers on the `/signal`
/// peer card, and is what both ends authenticate during the LAN handshake — ECDH against
/// it derives the channel key. This keypair is the entire basis of trust between two
/// paired devices, so the private half lives in the Keychain and never leaves.
///
/// Public keys cross platforms, so they travel as base64 **SPKI DER**: the encoding that
/// both `derRepresentation` here and `PublicKey.getEncoded()` on Android emit for the
/// same key.
public enum DeviceKey {
    private static let service = "com.fuseos.app"
    private static let account = "device-identity"

    enum Failure: Error, LocalizedError {
        case keychain(OSStatus)
        case malformedPeerKey

        var errorDescription: String? {
            switch self {
            case let .keychain(status): return "Keychain error \(status)."
            case .malformedPeerKey: return "Peer sent a public key that is not a P-256 SPKI key."
            }
        }
    }

    /// The device keypair, minted on first use and then reused forever.
    static func privateKey() throws -> P256.KeyAgreement.PrivateKey {
        if let stored = try readKeychain() {
            return try P256.KeyAgreement.PrivateKey(rawRepresentation: stored)
        }
        let key = P256.KeyAgreement.PrivateKey()
        try writeKeychain(key.rawRepresentation)
        return key
    }

    /// This device's public key as base64 SPKI DER — the `publicKey` the API expects.
    public static func publicKeyBase64() throws -> String {
        try privateKey().publicKey.derRepresentation.base64EncodedString()
    }

    /// Parses a peer's public key as delivered by the control plane.
    static func decodePublic(base64: String) throws -> P256.KeyAgreement.PublicKey {
        guard let der = Data(base64Encoded: base64) else { throw Failure.malformedPeerKey }
        do {
            return try P256.KeyAgreement.PublicKey(derRepresentation: der)
        } catch {
            throw Failure.malformedPeerKey
        }
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readKeychain() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw Failure.keychain(status)
        }
    }

    private static func writeKeychain(_ data: Data) throws {
        var query = baseQuery
        query[kSecValueData as String] = data

        // This lands in the file-based login keychain. The data-protection keychain
        // (and with it kSecAttrAccessible) needs a keychain-access-group entitlement,
        // which an ad-hoc signed app cannot carry — see build-app.sh.
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}
