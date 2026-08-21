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
    static let chunkBytes = 64 * 1024

    /// Bounds what one peer can make this device write to disk in a single transfer.
    public static let maxFileBytes = 1 << 30 // 1 GiB

    /// Where verified files land. Not the user's Downloads yet — choosing a destination is
    /// a UI decision, and this layer deliberately has no UI.
    public nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("FuseOS/Received", isDirectory: true)
    }

    /// Fires once per file, after the checksum has been verified. Nothing is published for
    /// a transfer that fails — a corrupt file is not an event worth showing anyone.
    public var onFileReceived: ((ReceivedFile) -> Void)?

    private let newEnvelope: () -> FuseEnvelope
    private let emit: (FuseEnvelope) async -> Void
    private let directory: URL
    private var receiving: [String: Reception] = [:]

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
    }

    /// Abandons every partial transfer. Called on teardown; the temp files go with it.
    public func stop() {
        for reception in receiving.values { reception.discard() }
        receiving.removeAll()
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

        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unreadable }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let block = try handle.read(upToCount: Self.chunkBytes), !block.isEmpty {
            hasher.update(data: block)
        }

        let transferId = UUID().uuidString
        var meta = newEnvelope()
        meta.fileMeta = FuseFileMeta.with {
            $0.transferID = transferId
            $0.name = url.lastPathComponent
            $0.size = UInt64(size)
            $0.mime = Self.mime(for: url)
            $0.checksum = hasher.finalize().hexString
        }
        await emit(meta)

        try handle.seek(toOffset: 0)
        var index: UInt64 = 0
        var sent = 0
        while true {
            let block = (try handle.read(upToCount: Self.chunkBytes)) ?? Data()
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
            if last { break }
            index += 1
        }
        return transferId
    }

    // MARK: - Receiving

    /// Feed every `FileMeta` / `FileChunk` / `Ack` envelope here.
    func receive(_ envelope: FuseEnvelope) {
        switch envelope.body {
        case let .some(.fileMeta(meta)): begin(meta)
        case let .some(.fileChunk(chunk)): append(chunk)
        // The sender has nothing left to do on an ack in v1 — no retry queue, no resume.
        // It stays on the wire because the receiver's "I have it, verified" is what a
        // progress UI will read in Day 3, and adding it later would be a protocol change.
        default: break
        }
    }

    private func begin(_ meta: FuseFileMeta) {
        // Peer-supplied and therefore untrusted: a name is a *file* name, never a path,
        // or "../../.ssh/authorized_keys" would be a valid transfer.
        let name = Self.safeName(meta.name)
        let size = Int(meta.size)
        guard size > 0, size <= Self.maxFileBytes, !meta.checksum.isEmpty else { return }
        // A repeated meta for a live transfer restarts it rather than corrupting it.
        receiving[meta.transferID]?.discard()

        let partial = directory.appendingPathComponent(".partial-\(Self.safeName(meta.transferID))")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: partial) else { return }
        receiving[meta.transferID] = Reception(
            transferId: meta.transferID, name: name, mime: meta.mime, size: size,
            checksum: meta.checksum.lowercased(), url: partial, handle: handle,
        )
    }

    private func append(_ chunk: FuseFileChunk) {
        guard let reception = receiving[chunk.transferID] else { return }
        // Ordering is the transport's job (TCP, one channel), so an out-of-order index
        // means something is wrong enough that the file cannot be trusted.
        guard chunk.index == reception.nextIndex else { return abandon(chunk.transferID) }
        reception.written += chunk.data.count
        guard reception.written <= reception.size else { return abandon(chunk.transferID) }
        do {
            try reception.handle.write(contentsOf: chunk.data)
        } catch {
            return abandon(chunk.transferID)
        }
        reception.hasher.update(data: chunk.data)
        reception.nextIndex += 1
        guard chunk.last else { return }
        finish(reception)
    }

    private func finish(_ reception: Reception) {
        receiving.removeValue(forKey: reception.transferId)
        try? reception.handle.close()
        guard reception.written == reception.size,
              reception.hasher.finalize().hexString == reception.checksum
        else {
            try? FileManager.default.removeItem(at: reception.url)
            FuseLog.lan.warning("file transfer failed verification, discarded")
            return
        }

        let destination = Self.uniqueURL(in: directory, name: reception.name)
        do {
            try FileManager.default.moveItem(at: reception.url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: reception.url)
            return
        }
        onFileReceived?(ReceivedFile(
            transferId: reception.transferId, url: destination, name: destination.lastPathComponent,
            mime: reception.mime, size: reception.size,
        ))

        var ack = newEnvelope()
        ack.ack = FuseAck.with { $0.refTransferID = reception.transferId }
        Task { await emit(ack) }
    }

    private func abandon(_ transferId: String) {
        receiving.removeValue(forKey: transferId)?.discard()
    }

    // MARK: - Helpers

    private final class Reception {
        let transferId: String
        let name: String
        let mime: String
        let size: Int
        let checksum: String
        let url: URL
        let handle: FileHandle
        var hasher = SHA256()
        var nextIndex: UInt64 = 0
        var written = 0

        init(
            transferId: String, name: String, mime: String, size: Int,
            checksum: String, url: URL, handle: FileHandle,
        ) {
            self.transferId = transferId
            self.name = name
            self.mime = mime
            self.size = size
            self.checksum = checksum
            self.url = url
            self.handle = handle
        }

        func discard() {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
        }
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
