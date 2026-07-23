import CryptoKit
import Foundation
import Network

/// One authenticated, encrypted connection to a paired device. The Android `LanChannel`
/// is the mirror of this file — the wire format below is the contract between them.
///
/// ```
/// handshake, plaintext, once:  [2-byte BE id length][device id UTF-8][32-byte nonce]
/// every frame after:           [4-byte BE length][AES-GCM ciphertext || 16-byte tag]
/// ```
///
/// The handshake carries a device id because the listening side sees only an IP address,
/// and the id is what lets it look up the public key the control plane vouched for. A
/// peer whose key we do not hold is not a peer, and the connection closes. Nothing is
/// decrypted before that check, so an unknown caller can never reach the envelope layer.
actor LanChannel {
    /// Bounds what a peer can make us allocate from a single length prefix.
    private static let maxFrameBytes = 4 * 1024 * 1024
    private static let maxDeviceIdBytes = 128

    enum Failure: Error {
        case closed
        case frameTooLarge(Int)
        case untrustedPeer(String)
        case selfConnection
    }

    nonisolated let peerDeviceId: String

    private let connection: NWConnection
    private let keys: LanCrypto.SessionKeys

    // Frame counters double as the GCM nonces, so they must move in lockstep with the
    // peer's. TCP guarantees the ordering that keeps them aligned.
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    private init(connection: NWConnection, keys: LanCrypto.SessionKeys, peerDeviceId: String) {
        self.connection = connection
        self.keys = keys
        self.peerDeviceId = peerDeviceId
    }

    func send(_ envelope: FuseEnvelope) async throws {
        let frame = try LanCrypto.seal(
            key: keys.send, counter: sendCounter, plaintext: try envelope.serializedData(),
        )
        sendCounter += 1
        try await connection.sendData(bigEndianLength(frame.count) + frame)
    }

    /// Throws at end of stream, on a malformed length, or when the tag check fails — all
    /// of which mean this connection is finished.
    func receive() async throws -> FuseEnvelope {
        let header = try await connection.receiveExactly(4)
        let length = Int(header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard length > 0, length <= Self.maxFrameBytes else {
            throw Failure.frameTooLarge(length)
        }
        let frame = try await connection.receiveExactly(length)
        let plaintext = try LanCrypto.open(
            key: keys.receive, counter: receiveCounter, ciphertext: frame,
        )
        receiveCounter += 1
        return try FuseEnvelope(serializedBytes: plaintext)
    }

    nonisolated func close() {
        connection.cancel()
    }

    /// Performs the handshake on an already-ready connection, in whichever direction.
    ///
    /// `trustedKeyFor` returns a peer's public key only if that peer is genuinely paired
    /// with this device — returning nil is what rejects a stranger.
    static func handshake(
        connection: NWConnection,
        selfDeviceId: String,
        privateKey: P256.KeyAgreement.PrivateKey,
        trustedKeyFor: @Sendable (String) -> P256.KeyAgreement.PublicKey?,
    ) async throws -> LanChannel {
        let selfNonce = LanCrypto.randomNonce()
        let selfId = Data(selfDeviceId.utf8)
        var idLength = UInt16(selfId.count).bigEndian
        let header = Data(bytes: &idLength, count: 2)
        try await connection.sendData(header + selfId + selfNonce)

        let peerLengthData = try await connection.receiveExactly(2)
        let peerIdLength = Int(peerLengthData.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
        guard peerIdLength > 0, peerIdLength <= maxDeviceIdBytes else {
            throw Failure.frameTooLarge(peerIdLength)
        }
        let peerIdData = try await connection.receiveExactly(peerIdLength)
        let peerNonce = try await connection.receiveExactly(LanCrypto.nonceLength)

        guard let peerId = String(data: peerIdData, encoding: .utf8) else {
            throw Failure.untrustedPeer("<malformed id>")
        }
        guard peerId != selfDeviceId else { throw Failure.selfConnection }
        guard let peerKey = trustedKeyFor(peerId) else { throw Failure.untrustedPeer(peerId) }

        let keys = try LanCrypto.sessionKeys(
            privateKey: privateKey,
            peerPublicKey: peerKey,
            selfDeviceId: selfDeviceId,
            peerDeviceId: peerId,
            selfNonce: selfNonce,
            peerNonce: peerNonce,
        )
        return LanChannel(connection: connection, keys: keys, peerDeviceId: peerId)
    }

    private func bigEndianLength(_ count: Int) -> Data {
        var value = UInt32(count).bigEndian
        return Data(bytes: &value, count: 4)
    }
}

// MARK: - async wrappers over Network.framework's callback API

extension NWConnection {
    /// Resolves once the connection is usable, or throws if it never gets there.
    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    // Clearing the handler first is what guarantees a single resume.
                    self?.stateUpdateHandler = nil
                    continuation.resume()
                case let .failed(error), let .waiting(error):
                    self?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    self?.stateUpdateHandler = nil
                    continuation.resume(throwing: LanChannel.Failure.closed)
                default:
                    break
                }
            }
        }
    }

    /// Reads exactly `count` bytes, or throws. Framed protocols need exact reads.
    func receiveExactly(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: LanChannel.Failure.closed)
                }
            }
        }
    }

    func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                },
            )
        }
    }
}
