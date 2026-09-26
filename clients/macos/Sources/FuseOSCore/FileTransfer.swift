import CoreServices
import CryptoKit
import Foundation

/// A file that arrived from a peer, verified and already on disk.
public struct ReceivedFile: Equatable, Identifiable {
    public var id: String { transferId }
    public let transferId: String
    public let url: URL
    public let name: String
    public let mime: String
    public let size: Int
}

/// Where one transfer is, for the progress UI. The Android `TransferProgress` is its mirror.
public struct TransferProgress: Equatable, Identifiable {
    public enum State: Equatable {
        /// Chunks are moving.
        case active
        /// Every chunk is out; waiting for the receiver's verified `Ack`. Outgoing only.
        case sent
        /// Acknowledged (outgoing) or verified and on disk (incoming).
        case done
        /// This device cancelled it.
        case cancelled
        /// The other end gave up, the link dropped, or the file failed verification.
        case failed
    }

    public var id: String { transferId }
    public let transferId: String
    public let name: String
    public let outgoing: Bool
    public let bytes: Int
    public let total: Int
    public let state: State

    public var finished: Bool { state == .done || state == .cancelled || state == .failed }

    public init(transferId: String, name: String, outgoing: Bool, bytes: Int, total: Int, state: State) {
        self.transferId = transferId
        self.name = name
        self.outgoing = outgoing
        self.bytes = bytes
        self.total = total
        self.state = state
    }
}

/// File transfer over the LAN data plane. The Android `FileTransfer` is the mirror of this
/// file; the two must stay in step, because the only thing between them is `proto/`.
///
/// The flow is `docs/protocol.md` §6: one `FileMeta` (name, size, mime, sha-256), then
/// ordered `FileChunk`s, then an `Ack` from the receiver once the checksum matches.
///
/// Deliberately not resumable. A dropped connection abandons the partial file and the user
/// re-sends — which on a LAN costs seconds, and costs far less code than a resume protocol
/// that would have to survive both ends restarting.
@MainActor
public final class FileTransfer {
    public enum Failure: Error, Equatable {
        case unreadable
        case empty
        case tooLarge(Int)
    }

    /// Small enough that a chunk is nowhere near `LanChannel`'s 4 MB frame cap even after
    /// protobuf framing and the GCM tag, large enough that a 100 MB file is ~1600 frames
    /// rather than 100k.
    nonisolated static let chunkBytes = 64 * 1024

    /// Bounds what one peer can make this device write to disk in a single transfer.
    public static let maxFileBytes = 1 << 30 // 1 GiB

    /// Where verified files land: the user's Downloads, which is where a Mac user looks
    /// for a file that came from somewhere else.
    public nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private static let partialPrefix = ".fuseos-partial-"

    /// Fires once per file, after the checksum has been verified. Nothing is published for
    /// a transfer that fails — a corrupt file is not an event worth showing anyone.
    public var onFileReceived: ((ReceivedFile) -> Void)?

    /// Every state change and roughly every 1% of bytes. Throttled because a 1 GiB file is
    /// 16k chunks, and a UI does not need 16k redraws.
    public var onProgress: ((TransferProgress) -> Void)?

    private let newEnvelope: () -> FuseEnvelope
    private let emit: (FuseEnvelope) async -> Void
    private let directory: URL
    private var receiving: [String: Reception] = [:]
    private var sending: [String: Outgoing] = [:]

    /// The transport init used by the app. Wiring the receive hook here rather than in a
    /// `start()` means a file cannot arrive before anyone is listening for it.
    public convenience init(transport: LanTransport, directory: URL = FileTransfer.defaultDirectory) {
        self.init(
            newEnvelope: { transport.newEnvelope() },
            emit: { await transport.send($0) },
            directory: directory,
        )
        transport.onFileEnvelope = { [weak self] envelope in self?.receive(envelope) }
    }

    /// Wire-facing init: everything this type does is expressible as "mint an envelope,
    /// emit it, write to a directory", which is also what makes it testable without a LAN.
    init(
        newEnvelope: @escaping () -> FuseEnvelope,
        emit: @escaping (FuseEnvelope) async -> Void,
        directory: URL,
    ) {
        self.newEnvelope = newEnvelope
        self.emit = emit
        self.directory = directory
        // A partial is only ever alive inside one process: one left on disk is from a run
        // that was killed mid-transfer, and nothing will ever finish it.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in leftovers where name.hasPrefix(Self.partialPrefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Abandons every partial transfer. Called on teardown; the temp files go with it.
    public func stop() {
        for reception in receiving.values { reception.discard() }
        receiving.removeAll()
        for outgoing in sending.values { outgoing.cancelled = true }
        sending.removeAll()
    }

    /// Stops a transfer in either direction and tells the other end, which discards its
    /// side. A no-op for an id that already finished.
    public func cancel(_ transferId: String) {
        if let outgoing = sending.removeValue(forKey: transferId) {
            // The send loop sees the flag after its current chunk and stops quietly; the
            // cancel below is what the receiver acts on.
            outgoing.cancelled = true
            emitCancel(transferId)
            report(outgoing.progress(.cancelled))
            return
        }
        guard let reception = receiving.removeValue(forKey: transferId) else { return }
        reception.discard()
        emitCancel(transferId)
        report(reception.progress(.cancelled))
    }

    /// Fails whatever cannot finish now that only `connected` peers are reachable: an
    /// incoming file from a peer that dropped will never get its last chunk, and with nobody
    /// connected an outgoing one will never be acknowledged.
    public func peersChanged(_ connected: Set<String>) {
        for reception in receiving.values where !connected.contains(reception.sourceDeviceId) {
            receiving.removeValue(forKey: reception.transferId)
            reception.discard()
            report(reception.progress(.failed))
        }
        guard connected.isEmpty else { return }
        for outgoing in sending.values {
            outgoing.cancelled = true
            report(outgoing.progress(.failed))
        }
        sending.removeAll()
    }

    // MARK: - Sending

    /// Streams a file to every connected peer, returning its transfer id.
    ///
    /// Two passes over the file: one to checksum it, one to send it. `FileMeta` has to
    /// carry the checksum, and the receiver has to be able to verify before it commits the
    /// file anywhere — so the hash cannot be computed as we go.
    ///
    /// ponytail: reads on the main actor in 64 KB slices, each separated by an `await` on
    /// the actual network write, so the run loop breathes between them. Move the reader to
    /// a detached task if a large file ever janks the UI.
    @discardableResult
    public func send(fileAt url: URL) async throws -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { throw Failure.unreadable }
        guard size > 0 else { throw Failure.empty }
        guard size <= Self.maxFileBytes else { throw Failure.tooLarge(size) }

        // Off the main actor: hashing a gigabyte takes seconds, and on the main actor those
        // seconds were a frozen window. The send loop below awaits every write, so it can
        // stay here.
        let checksum = try await Task.detached(priority: .userInitiated) {
            try Self.sha256(of: url)
        }.value

        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unreadable }
        defer { try? handle.close() }

        let transferId = UUID().uuidString
        let outgoing = Outgoing(transferId: transferId, name: url.lastPathComponent, size: size)
        sending[transferId] = outgoing
        report(outgoing.progress(.active))
        var meta = newEnvelope()
        meta.fileMeta = FuseFileMeta.with {
            $0.transferID = transferId
            $0.name = url.lastPathComponent
            $0.size = UInt64(size)
            $0.mime = Self.mime(for: url)
            $0.checksum = checksum
        }
        await emit(meta)

        var index: UInt64 = 0
        var sent = 0
        while true {
            // Cancelled from the UI, or failed by a dropped peer: whoever set the flag has
            // already reported it and told the receiver.
            if outgoing.cancelled { return transferId }
            let block: Data
            do {
                block = (try handle.read(upToCount: Self.chunkBytes)) ?? Data()
            } catch {
                // Unreadable halfway: the receiver holds a partial that will never finish,
                // so it has to be told rather than left to wait.
                if sending.removeValue(forKey: transferId) != nil {
                    emitCancel(transferId)
                    report(outgoing.progress(.failed))
                }
                throw Failure.unreadable
            }
            sent += block.count
            // The file shrinking mid-send ends the stream here; the receiver's checksum is
            // what catches it, which is the same check that catches a corrupted chunk.
            let last = block.isEmpty || sent >= size
            var envelope = newEnvelope()
            envelope.fileChunk = FuseFileChunk.with {
                $0.transferID = transferId
                $0.index = index
                $0.data = block
                $0.last = last
            }
            await emit(envelope)
            // Checked after the write as well: a cancel that lands while a chunk is on its
            // way must not be followed by an "active" report.
            if outgoing.cancelled { return transferId }
            outgoing.bytes = sent
            if last { break }
            index += 1
            if outgoing.shouldReport() { report(outgoing.progress(.active)) }
        }
        // Still ours unless an ack or a cancel raced the last chunk.
        if sending[transferId] != nil { report(outgoing.progress(.sent)) }
        return transferId
    }

    // MARK: - Receiving

    /// Feed every `FileMeta` / `FileChunk` / `Ack` envelope here.
    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case let .some(.fileMeta(meta)): begin(meta, from: envelope.sourceDeviceID)
        case let .some(.fileChunk(chunk)): append(chunk)
        case let .some(.ack(ack)): acknowledged(ack.refTransferID)
        case let .some(.fileCancel(cancel)): cancelledRemotely(cancel.transferID)
        default: break
        }
    }

    /// The receiver has the file and it verified: the only point a send is really done.
    private func acknowledged(_ transferId: String) {
        guard let outgoing = sending.removeValue(forKey: transferId) else { return }
        report(outgoing.progress(.done, bytes: outgoing.size))
    }

    /// The other end gave up. Same handling whichever end of the transfer we are.
    private func cancelledRemotely(_ transferId: String) {
        if let outgoing = sending.removeValue(forKey: transferId) {
            outgoing.cancelled = true
            report(outgoing.progress(.failed))
            return
        }
        guard let reception = receiving.removeValue(forKey: transferId) else { return }
        reception.discard()
        report(reception.progress(.failed))
    }

    private func begin(_ meta: FuseFileMeta, from sourceDeviceId: String) {
        // Peer-supplied and therefore untrusted: a name is a *file* name, never a path,
        // or "../../.ssh/authorized_keys" would be a valid transfer.
        let name = Self.safeName(meta.name)
        // Bounds-checked while still a UInt64: `Int(meta.size)` traps on anything above
        // Int.max, so a peer sending a huge size would have crashed the app.
        guard meta.size > 0, meta.size <= UInt64(Self.maxFileBytes), !meta.checksum.isEmpty else { return }
        let size = Int(meta.size)
        // A repeated meta for a live transfer restarts it rather than corrupting it.
        receiving[meta.transferID]?.discard()

        let partial = directory.appendingPathComponent("\(Self.partialPrefix)\(Self.safeName(meta.transferID))")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: partial) else { return }
        let reception = Reception(
            transferId: meta.transferID, sourceDeviceId: sourceDeviceId, name: name,
            mime: meta.mime, size: size, checksum: meta.checksum.lowercased(), url: partial,
            handle: handle,
        )
        receiving[meta.transferID] = reception
        report(reception.progress(.active))
    }

    private func append(_ chunk: FuseFileChunk) {
        guard let reception = receiving[chunk.transferID] else { return }
        // Ordering is the transport's job (TCP, one channel), so an out-of-order index
        // means something is wrong enough that the file cannot be trusted.
        guard chunk.index == reception.nextIndex else { return abandon(reception) }
        reception.written += chunk.data.count
        guard reception.written <= reception.size else { return abandon(reception) }
        do {
            try reception.handle.write(contentsOf: chunk.data)
        } catch {
            return abandon(reception)
        }
        reception.hasher.update(data: chunk.data)
        reception.nextIndex += 1
        guard chunk.last else {
            if reception.shouldReport() { report(reception.progress(.active)) }
            return
        }
        finish(reception)
    }

    private func finish(_ reception: Reception) {
        receiving.removeValue(forKey: reception.transferId)
        try? reception.handle.close()
        guard reception.written == reception.size,
              reception.hasher.finalize().hexString == reception.checksum
        else {
            FuseLog.lan.warning("file transfer failed verification, discarded")
            return fail(reception)
        }

        let destination = Self.uniqueURL(in: directory, name: reception.name)
        do {
            try FileManager.default.moveItem(at: reception.url, to: destination)
        } catch {
            return fail(reception)
        }
        Self.quarantine(destination)
        report(reception.progress(.done))
        onFileReceived?(ReceivedFile(
            transferId: reception.transferId, url: destination, name: destination.lastPathComponent,
            mime: reception.mime, size: reception.size,
        ))

        var ack = newEnvelope()
        ack.ack = FuseAck.with { $0.refTransferID = reception.transferId }
        Task { await emit(ack) }
    }

    /// Drops a reception that went wrong, and tells the sender so it stops waiting.
    private func abandon(_ reception: Reception) {
        receiving.removeValue(forKey: reception.transferId)
        fail(reception)
    }

    private func fail(_ reception: Reception) {
        reception.discard()
        emitCancel(reception.transferId)
        report(reception.progress(.failed))
    }

    private func emitCancel(_ transferId: String) {
        var envelope = newEnvelope()
        envelope.fileCancel = FuseFileCancel.with { $0.transferID = transferId }
        Task { await emit(envelope) }
    }

    private func report(_ progress: TransferProgress) {
        onProgress?(progress)
    }

    // MARK: - Helpers

    /// What both directions share: a byte count to report, throttled to about 1%.
    private class Tracked {
        let transferId: String
        let name: String
        let size: Int
        var outgoing: Bool { false }
        var bytesDone: Int { 0 }
        private var reportedAt = 0

        init(transferId: String, name: String, size: Int) {
            self.transferId = transferId
            self.name = name
            self.size = size
        }

        func shouldReport() -> Bool {
            guard bytesDone - reportedAt >= size / 100 else { return false }
            reportedAt = bytesDone
            return true
        }

        func progress(_ state: TransferProgress.State, bytes: Int? = nil) -> TransferProgress {
            TransferProgress(
                transferId: transferId, name: name, outgoing: outgoing,
                bytes: bytes ?? bytesDone, total: size, state: state,
            )
        }
    }

    private final class Outgoing: Tracked {
        var bytes = 0
        var cancelled = false
        override var outgoing: Bool { true }
        override var bytesDone: Int { bytes }
    }

    private final class Reception: Tracked {
        let sourceDeviceId: String
        let mime: String
        let checksum: String
        let url: URL
        let handle: FileHandle
        var hasher = SHA256()
        var nextIndex: UInt64 = 0
        var written = 0
        override var bytesDone: Int { written }

        init(
            transferId: String, sourceDeviceId: String, name: String, mime: String, size: Int,
            checksum: String, url: URL, handle: FileHandle,
        ) {
            self.sourceDeviceId = sourceDeviceId
            self.mime = mime
            self.checksum = checksum
            self.url = url
            self.handle = handle
            super.init(transferId: transferId, name: name, size: size)
        }

        func discard() {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Marks a received file as downloaded, the way a browser or AirDrop does, so Gatekeeper
    /// checks an app or script from the phone before it first runs. The sender is the
    /// user's own device, but a phone can download malware too.
    private static func quarantine(_ url: URL) {
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
            kLSQuarantineAgentNameKey as String: "FuseOS",
        ]
        var url = url
        try? url.setResourceValues(values)
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unreadable }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: chunkBytes), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().hexString
    }

    /// Reduces anything a peer sends to a plain file name. Internal so the traversal cases
    /// are tested rather than assumed.
    static func safeName(_ raw: String) -> String {
        let name = (raw as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        guard !name.isEmpty, name != ".", name != ".." else { return "file" }
        return String(name.prefix(255))
    }

    /// Never overwrites: a second `report.pdf` becomes `report-1.pdf`.
    static func uniqueURL(in directory: URL, name: String) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for suffix in 1 ... 999 {
            let numbered = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            let url = directory.appendingPathComponent(numbered)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString)")
    }

    private static func mime(for url: URL) -> String {
        // ponytail: extension lookup only. UTType covers the rest if a peer ever needs
        // more than "is this an image".
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}

extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
