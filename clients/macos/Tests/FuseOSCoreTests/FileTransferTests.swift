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
    private var senderProgress: [TransferProgress] = []
    private var receiverProgress: [TransferProgress] = []
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
        senderProgress = []
        receiverProgress = []
        sender.onProgress = { [unowned self] in self.senderProgress.append($0) }
        receiver.onProgress = { [unowned self] in self.receiverProgress.append($0) }
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

    private func transferId(of envelopes: [FuseEnvelope]) -> String {
        for envelope in envelopes { if case let .some(.fileMeta(meta)) = envelope.body { return meta.transferID } }
        return ""
    }

    /// Feeds whatever the receiver emitted (ack, cancel) back to the sender.
    private func replyAll() async {
        let envelopes = sent
        sent = []
        envelopes.forEach { sender.receive($0) }
        await settle()
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
        // No ack — the sender is told it failed instead.
        XCTAssertEqual(sent.count, 1)
        guard case let .some(.fileCancel(cancel)) = sent.first?.body else { return XCTFail("expected a cancel") }
        XCTAssertEqual(cancel.transferID, transferId(of: envelopes))
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

    func testSendIsDoneOnlyOnceTheReceiverAcknowledgesIt() async throws {
        let data = randomData(FileTransfer.chunkBytes * 3, seed: 19)
        _ = try await sender.send(fileAt: try write(data))
        XCTAssertEqual(senderProgress.last?.state, .sent)
        await deliverAll()
        XCTAssertEqual(receiverProgress.last?.state, .done)
        await replyAll()
        XCTAssertEqual(senderProgress.last?.state, .done)
        XCTAssertEqual(senderProgress.last?.bytes, data.count)
    }

    func testCancellingASendStopsTheStreamAndTheReceiverDiscardsItsPartial() async throws {
        let data = randomData(FileTransfer.chunkBytes * 10, seed: 23)
        let url = try write(data)
        var cancelling: FileTransfer!
        cancelling = FileTransfer(
            newEnvelope: { [unowned self] in self.envelope() },
            emit: { [unowned self] envelope in
                self.sent.append(envelope)
                // Cancel from inside the stream, the way the UI's button lands mid-transfer.
                if case let .some(.fileChunk(chunk)) = envelope.body, chunk.index == 2 {
                    cancelling.cancel(chunk.transferID)
                }
            },
            directory: root.appendingPathComponent("out2", isDirectory: true),
        )
        cancelling.onProgress = { [unowned self] in self.senderProgress.append($0) }
        _ = try await cancelling.send(fileAt: url)
        await settle()

        XCTAssertEqual(sent.filter { if case .some(.fileChunk) = $0.body { return true } else { return false } }.count, 3)
        XCTAssertEqual(senderProgress.last?.state, .cancelled)
        await deliverAll()
        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(inboxContents().isEmpty)
        XCTAssertEqual(receiverProgress.last?.state, .failed)
    }

    func testCancellingAReceiveTellsTheSender() async throws {
        _ = try await sender.send(fileAt: try write(randomData(FileTransfer.chunkBytes * 2, seed: 29)))
        let envelopes = sent
        sent = []
        receiver.receive(envelopes[0]) // meta only
        receiver.cancel(transferId(of: envelopes))
        await settle()

        XCTAssertTrue(inboxContents().isEmpty)
        XCTAssertEqual(receiverProgress.last?.state, .cancelled)
        await replyAll()
        XCTAssertEqual(senderProgress.last?.state, .failed)
    }

    func testPeerDroppingMidTransferDiscardsItsPartial() async throws {
        _ = try await sender.send(fileAt: try write(randomData(FileTransfer.chunkBytes * 3, seed: 37)))
        sent.prefix(2).forEach { receiver.receive($0) } // meta + first chunk
        XCTAssertEqual(inboxContents().count, 1) // the partial

        receiver.peersChanged(["some-other-device"])
        XCTAssertTrue(inboxContents().isEmpty)
        XCTAssertEqual(receiverProgress.last?.state, .failed)
    }

    func testPartialLeftByAKilledProcessIsSweptOnTheNextStart() throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: inbox.appendingPathComponent(".fuseos-partial-stale"))
        try Data("real".utf8).write(to: inbox.appendingPathComponent("kept.txt"))
        _ = FileTransfer(newEnvelope: { FuseEnvelope() }, emit: { _ in }, directory: inbox)
        XCTAssertEqual(inboxContents(), ["kept.txt"])
    }

    func testAnAbsurdSizeFromAPeerIsRefusedRatherThanCrashing() async {
        var envelope = envelope()
        envelope.fileMeta = FuseFileMeta.with {
            $0.transferID = "t"
            $0.name = "x"
            $0.size = UInt64.max // Int(UInt64.max) traps
            $0.checksum = "00"
        }
        receiver.receive(envelope)
        XCTAssertTrue(receiverProgress.isEmpty)
    }
}
