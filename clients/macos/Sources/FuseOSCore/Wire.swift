import Foundation
import Network

/// What a `LanChannel` runs over (Android's `Wire`): a LAN connection, or the relay through
/// `/signal`. The channel, its keys and its checks are the same either way, so the relay is
/// exactly as private as the LAN (docs/protocol.md §19).
protocol Wire: AnyObject, Sendable {
    var viaRelay: Bool { get }
    func sendData(_ data: Data) async throws
    func receiveExactly(_ count: Int) async throws -> Data
    func cancel()
}

extension NWConnection: Wire {
    var viaRelay: Bool { false }
}

/// One relayed channel to `peerId`. Writes leave as relay messages of at most `chunk` bytes;
/// reads take the pieces `deliver` hands over, in order.
final class RelayWire: Wire, @unchecked Sendable {
    /// Matches the server's limit (server/src/signal/relay.ts RELAY_CHUNK_BYTES).
    static let chunk = 64 * 1024

    let peerId: String
    let stream: String
    let viaRelay = true
    private let sendPiece: @Sendable (Data?, Bool) -> Bool

    private let lock = NSLock()
    private var buffer = Data()
    private var ended = false
    private var waiter: (count: Int, continuation: CheckedContinuation<Data, Error>)?

    init(peerId: String, stream: String, send: @escaping @Sendable (Data?, Bool) -> Bool) {
        self.peerId = peerId
        self.stream = stream
        sendPiece = send
    }

    func deliver(_ data: Data) {
        lock.lock()
        if !ended { buffer.append(data) }
        let ready = takeReady()
        lock.unlock()
        ready?()
    }

    /// The peer closed the stream: reads end.
    func end() {
        lock.lock()
        ended = true
        let ready = takeReady()
        lock.unlock()
        ready?()
    }

    func receiveExactly(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            waiter = (count, continuation)
            let ready = takeReady()
            lock.unlock()
            ready?()
        }
    }

    func sendData(_ data: Data) async throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(data.endIndex, offset + Self.chunk)
            guard sendPiece(data.subdata(in: offset ..< end), false) else { throw LanChannel.Failure.closed }
            offset = end
        }
    }

    func cancel() {
        lock.lock()
        let wasOpen = !ended
        ended = true
        let ready = takeReady()
        lock.unlock()
        ready?()
        if wasOpen { _ = sendPiece(nil, true) }
    }

    /// With the lock held: the resume for a waiting read that can now finish, run after unlocking.
    private func takeReady() -> (() -> Void)? {
        guard let waiting = waiter else { return nil }
        if buffer.count >= waiting.count {
            let out = Data(buffer.prefix(waiting.count))
            buffer = Data(buffer.dropFirst(waiting.count))
            waiter = nil
            return { waiting.continuation.resume(returning: out) }
        }
        if ended {
            waiter = nil
            return { waiting.continuation.resume(throwing: LanChannel.Failure.closed) }
        }
        return nil
    }
}

/// What a relayed channel carries (§19): copies, notifications, commands and heartbeats — not
/// files, mirroring, Sidecar or the history catch-up, nor anything over 256 KB.
enum Relay {
    static let maxEnvelopeBytes = 256 * 1024

    static func carries(_ envelope: FuseEnvelope) -> Bool {
        switch envelope.body {
        case .fileMeta, .fileChunk, .fileCancel, .screenControl, .screenFrame, .remoteInput,
             .sidecarControl, .sidecarFrame, .sidecarInput, .historySync:
            return false
        default:
            return ((try? envelope.serializedData().count) ?? .max) <= maxEnvelopeBytes
        }
    }
}
