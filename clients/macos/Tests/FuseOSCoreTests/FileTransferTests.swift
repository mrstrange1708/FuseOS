@testable import FuseOSCore
import CryptoKit
import Foundation
import XCTest

/// Drives a sender straight into a receiver, which is the pair that has to agree — the
/// Android `FileTransferTest` runs the same shapes against the same wire format, so the
/// two clients are tested against one contract rather than against each other's
/// assumptions.
@MainActor
final class FileTransferTests: XCTestCase {

    private var root: URL!
    private var inbox: URL!
    private var sent: [FuseEnvelope] = []
    private var received: [ReceivedFile] = []
    private var seq: UInt64 = 0
    private var sender: FileTransfer!
    private var receiver: FileTransfer!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fuse-file-\(UUID().uuidString)", isDirectory: true)
        inbox = root.appendingPathComponent("in", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sent = []
        received = []
        seq = 0

        sender = FileTransfer(
            newEnvelope: { [unowned self] in self.envelope() },
            emit: { [unowned self] in self.sent.append($0) },
            directory: root.appendingPathComponent("out", isDirectory: true),
        )
        receiver = FileTransfer(
            newEnvelope: { [unowned self] in self.envelope() },
            emit: { [unowned self] in self.sent.append($0) },
            directory: inbox,
        )
        receiver.onFileReceived = { [unowned self] in self.received.append($0) }
    }

    override func tearDown() async throws {
        sender.stop()
        receiver.stop()
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func envelope() -> FuseEnvelope {
        seq += 1
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = "device-a"
        envelope.seq = seq
        envelope.sessionID = "session"
        return envelope
    }

    /// Everything the sender emitted, replayed into the receiver in wire order.
    ///
    /// The trailing yields let the receiver's ack — sent from a `Task`, because emitting is
    /// async and `finish` is not — actually run before anything is asserted about it.
    private func deliverAll() async {
        let envelopes = sent
        sent = []
        envelopes.forEach { receiver.receive($0) }
        await settle()
    }

    private func settle() async {
        for _ in 0 ..< 5 { await Task.yield() }
    }

    private func write(_ data: Data, name: String = "notes.txt") throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func randomData(_ count: Int, seed: UInt64) -> Data {
        var value = seed | 1
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0 ..< count {
            value ^= value << 13
            value ^= value >> 7
            value ^= value << 17
            bytes.append(UInt8(truncatingIfNeeded: value))
        }
        return Data(bytes)
    }

    private func inboxContents() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []
    }

    func testFileArrivesByteIdenticalAndIsAcknowledged() async throws {
        // Deliberately several chunks plus a partial one — off-by-one on the last chunk is
        // the failure this catches.
        let data = randomData(FileTransfer.chunkBytes * 2 + 123, seed: 7)
        _ = try await sender.send(fileAt: try write(data))
        await deliverAll()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(try Data(contentsOf: received[0].url), data)
        XCTAssertEqual(received[0].name, "notes.txt")
        XCTAssertEqual(sent.filter { if case .some(.ack) = $0.body { return true } else { return false } }.count, 1)
    }

    func testFileOfExactlyOneChunkTerminates() async throws {
        let data = randomData(FileTransfer.chunkBytes, seed: 1)
        _ = try await sender.send(fileAt: try write(data))
        await deliverAll()
        XCTAssertEqual(try Data(contentsOf: received[0].url), data)
    }

    func testCorruptedChunkIsDiscardedRatherThanWrittenOut() async throws {
        let data = randomData(FileTransfer.chunkBytes + 10, seed: 3)
        _ = try await sender.send(fileAt: try write(data))
        let envelopes = sent.map { envelope -> FuseEnvelope in
            guard case let .some(.fileChunk(chunk)) = envelope.body, chunk.index == 0 else {
                return envelope
            }
            var corrupted = envelope
            corrupted.fileChunk.data = Data(repeating: 0, count: FileTransfer.chunkBytes)
            return corrupted
        }
        sent = []
        envelopes.forEach { receiver.receive($0) }
        await settle()

        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(sent.isEmpty)
        // And nothing is left behind on disk — not the partial, not a half file.
        XCTAssertTrue(inboxContents().isEmpty)
    }

    func testChunkOutOfOrderAbandonsTheTransfer() async throws {
        let data = randomData(FileTransfer.chunkBytes * 2, seed: 5)
        _ = try await sender.send(fileAt: try write(data))
        let envelopes = sent
        sent = []
        // Drop chunk 0: chunk 1 then arrives where 0 was expected.
        for envelope in envelopes {
            if case let .some(.fileChunk(chunk)) = envelope.body, chunk.index == 0 { continue }
            receiver.receive(envelope)
        }
        await settle()

        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(inboxContents().isEmpty)
    }

    func testTwoFilesOfTheSameNameBothSurvive() async throws {
        let first = randomData(64, seed: 11)
        let second = randomData(64, seed: 12)
        _ = try await sender.send(fileAt: try write(first))
        await deliverAll()
        _ = try await sender.send(fileAt: try write(second))
        await deliverAll()

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(try Data(contentsOf: received[0].url), first)
        XCTAssertEqual(try Data(contentsOf: received[1].url), second)
        XCTAssertNotEqual(received[0].name, received[1].name)
    }

    func testEmptyFileIsRefusedRatherThanSent() async throws {
        let url = try write(Data())
        do {
            _ = try await sender.send(fileAt: url)
            XCTFail("an empty file should not be sendable")
        } catch {
            XCTAssertEqual(error as? FileTransfer.Failure, .empty)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testChecksumOnTheWireIsTheSha256OfTheContent() async throws {
        let data = randomData(1000, seed: 13)
        _ = try await sender.send(fileAt: try write(data))
        guard case let .some(.fileMeta(meta)) = sent.first?.body else {
            return XCTFail("the first envelope must be the meta")
        }
        XCTAssertEqual(meta.checksum, SHA256.hash(data: data).hexString)
        XCTAssertEqual(meta.size, UInt64(data.count))
    }

    func testPeerCannotWriteOutsideTheDownloadDirectory() {
        XCTAssertEqual(FileTransfer.safeName("../../../etc/passwd"), "passwd")
        XCTAssertEqual(FileTransfer.safeName(".."), "file")
        XCTAssertEqual(FileTransfer.safeName(""), "file")
        XCTAssertEqual(FileTransfer.safeName("notes.txt"), "notes.txt")
    }

    func testNameAPeerChoseIsConfinedToTheDirectoryOnARealTransfer() async throws {
        let data = randomData(32, seed: 17)
        _ = try await sender.send(fileAt: try write(data))
        // Rewrite the name on the wire the way a hostile peer would.
        let envelopes = sent.map { envelope -> FuseEnvelope in
            guard case .some(.fileMeta) = envelope.body else { return envelope }
            var renamed = envelope
            renamed.fileMeta.name = "../../escape.txt"
            return renamed
        }
        sent = []
        envelopes.forEach { receiver.receive($0) }
        await settle()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].url.deletingLastPathComponent().standardizedFileURL, inbox.standardizedFileURL)
        XCTAssertEqual(received[0].name, "escape.txt")
    }
}
