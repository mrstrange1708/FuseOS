@testable import FuseOSCore
import XCTest

/// The loop-prevention rules from `docs/protocol.md` §4. A regression here does not throw;
/// it makes two real devices overwrite each other's clipboard in a loop, which is why
/// these cases are pinned down in-process.
///
/// Deliberately the same scenarios as Android's `LoopGuardTest` — the two implementations
/// must not drift, because they are the two halves of one protocol.
final class LoopGuardTests: XCTestCase {

    private func guardFor(_ id: String = "self") -> LoopGuard {
        LoopGuard(selfDeviceId: id)
    }

    func testAppliesAFreshEventFromAPeer() {
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: 1, sentAtUnixMs: 100))
    }

    func testNeverAppliesAnEventWeOriginated() {
        // The echo of our own copy coming back is the first half of a sync loop.
        var g = guardFor()
        XCTAssertFalse(g.shouldApply(sourceDeviceId: "self", seq: 1, sentAtUnixMs: 100))
    }

    func testIgnoresAReplayedOrDuplicatedSequenceNumber() {
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: 5, sentAtUnixMs: 100))
        XCTAssertFalse(g.shouldApply(sourceDeviceId: "peer", seq: 5, sentAtUnixMs: 100))
        XCTAssertFalse(g.shouldApply(sourceDeviceId: "peer", seq: 4, sentAtUnixMs: 100))
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: 6, sentAtUnixMs: 101))
    }

    func testTracksSequenceNumbersPerSourceDevice() {
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer-a", seq: 9, sentAtUnixMs: 100))
        // A different device's low sequence number is not a duplicate.
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer-b", seq: 1, sentAtUnixMs: 100))
    }

    func testAStragglerDoesNotOverwriteNewerContent() {
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: 1, sentAtUnixMs: 500))
        g.recordApplied(contentHash: LoopGuard.hash("newer"), sentAtUnixMs: 500)
        XCTAssertFalse(g.shouldApply(sourceDeviceId: "peer", seq: 2, sentAtUnixMs: 400))
    }

    /// The boundary of the last-write-wins comparison. Equal timestamps must be ACCEPTED
    /// — two devices' clocks agreeing to the millisecond is normal on a LAN, and
    /// rejecting equality would silently drop legitimate copies.
    func testAnEventWithAnEqualTimestampIsStillApplied() {
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: 1, sentAtUnixMs: 500))
        g.recordApplied(contentHash: LoopGuard.hash("first"), sentAtUnixMs: 500)
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: 2, sentAtUnixMs: 500))
    }

    func testSwallowsTheEchoOfContentItJustInjected() {
        var g = guardFor()
        let text = "copied on the phone"
        g.recordApplied(contentHash: LoopGuard.hash(text), sentAtUnixMs: 100)
        XCTAssertFalse(g.shouldEmit(contentHash: LoopGuard.hash(text)))
    }

    func testSuppressionIsOneShotSoADeliberateReCopyStillSyncs() {
        var g = guardFor()
        let text = "shared text"
        g.recordApplied(contentHash: LoopGuard.hash(text), sentAtUnixMs: 100)
        XCTAssertFalse(g.shouldEmit(contentHash: LoopGuard.hash(text))) // the injection echo
        XCTAssertTrue(g.shouldEmit(contentHash: LoopGuard.hash(text))) // the user re-copying
    }

    func testEmitsUnrelatedLocalCopies() {
        var g = guardFor()
        g.recordApplied(contentHash: LoopGuard.hash("from peer"), sentAtUnixMs: 100)
        XCTAssertTrue(g.shouldEmit(contentHash: LoopGuard.hash("something else")))
    }

    func testAFullRoundTripBetweenTwoDevicesSettlesInsteadOfLooping() {
        // Mirrors what happens on real hardware: A copies, B applies, B's clipboard
        // watcher fires, and B must not send it back.
        var deviceA = LoopGuard(selfDeviceId: "A")
        var deviceB = LoopGuard(selfDeviceId: "B")
        let hash = LoopGuard.hash("hello")

        XCTAssertTrue(deviceA.shouldEmit(contentHash: hash))
        XCTAssertTrue(deviceB.shouldApply(sourceDeviceId: "A", seq: 1, sentAtUnixMs: 100))
        deviceB.recordApplied(contentHash: hash, sentAtUnixMs: 100)
        XCTAssertFalse(deviceB.shouldEmit(contentHash: hash)) // the loop ends here
    }

    func testInterleavedEventsFromTwoPeersDoNotInterfere() {
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "A", seq: 1, sentAtUnixMs: 100))
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "B", seq: 1, sentAtUnixMs: 101))
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "A", seq: 2, sentAtUnixMs: 102))
        XCTAssertFalse(g.shouldApply(sourceDeviceId: "B", seq: 1, sentAtUnixMs: 103)) // replay
    }

    func testHandlesVeryLargeSequenceNumbers() {
        // seq is a uint64 on the wire; a device that has been up a long time must not
        // wrap into rejecting everything.
        var g = guardFor()
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: UInt64.max - 1, sentAtUnixMs: 100))
        XCTAssertTrue(g.shouldApply(sourceDeviceId: "peer", seq: UInt64.max, sentAtUnixMs: 101))
        XCTAssertFalse(g.shouldApply(sourceDeviceId: "peer", seq: UInt64.max, sentAtUnixMs: 102))
    }

    // MARK: - Hashing

    func testIdenticalContentHashesIdenticallyAndDifferentContentDoesNot() {
        XCTAssertEqual(LoopGuard.hash("same"), LoopGuard.hash("same"))
        XCTAssertNotEqual(LoopGuard.hash("one"), LoopGuard.hash("two"))
    }

    /// Pins the hash to standard SHA-256 hex. Android's `LoopGuard.hash` must produce the
    /// same string — the two only interoperate if this exact encoding is shared.
    func testHashIsPlainLowercaseSha256Hex() {
        XCTAssertEqual(
            LoopGuard.hash("hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        )
    }

    func testTextAndByteHashingAgreeForTheSameContent() {
        // Images hash bytes, text hashes UTF-8 — the two paths must not disagree.
        XCTAssertEqual(LoopGuard.hash("abc"), LoopGuard.hash(Data("abc".utf8)))
    }
}
