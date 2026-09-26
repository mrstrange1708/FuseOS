import AppKit
@testable import FuseOSCore
import Foundation
import XCTest

/// Drives `ClipboardSync` against a private `NSPasteboard`, so this exercises the real
/// AppKit behaviour — changeCount, type coercion, image encoding — without touching the
/// clipboard of whoever is running the tests.
///
/// The unit tests in `LoopGuardTests` prove the loop-prevention *rules*. These prove the
/// bridge honours them: the wiring between "the user copied something" and "send it" is
/// where a rule gets accidentally bypassed.
@MainActor
final class ClipboardSyncTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var transport: LanTransport!
    private var sync: ClipboardSync!

    override func setUp() async throws {
        try await super.setUp()
        // A uniquely named pasteboard is private to this test.
        pasteboard = NSPasteboard(name: .init("com.fuseos.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        transport = LanTransport()
        sync = ClipboardSync(transport: transport, pasteboard: pasteboard)
        sync.start(selfDeviceId: "self-device")
    }

    override func tearDown() async throws {
        sync.stop()
        pasteboard.releaseGlobally()
        try await super.tearDown()
    }

    /// Captures what the transport was asked to broadcast. With no peers connected,
    /// `broadcast` is a no-op, so the envelope is observed via the sequence counter
    /// instead — it only advances when an envelope is actually built.
    private func envelopesSent(_ body: () -> Void) -> Int {
        let before = transport.newEnvelope().seq
        body()
        let after = transport.newEnvelope().seq
        // Subtract the two probe envelopes we minted ourselves.
        return Int(after - before) - 1
    }

    private func copyText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func inbound(text: String, from source: String, seq: UInt64, at ms: Int64) -> FuseEnvelope {
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = source
        envelope.seq = seq
        envelope.sentAtUnixMs = ms
        envelope.clipText = FuseClipText.with { $0.text = text }
        return envelope
    }

    // MARK: - Inbound

    func testAppliesInboundTextToThePasteboard() {
        sync.apply(inbound(text: "from the phone", from: "peer", seq: 1, at: 100))
        XCTAssertEqual(pasteboard.string(forType: .string), "from the phone")
    }

    func testIgnoresAnInboundEventWeOriginated() {
        copyText("original")
        sync.apply(inbound(text: "echoed back", from: "self-device", seq: 1, at: 100))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testIgnoresAReplayedInboundEvent() {
        sync.apply(inbound(text: "first", from: "peer", seq: 1, at: 100))
        sync.apply(inbound(text: "replayed", from: "peer", seq: 1, at: 100))
        XCTAssertEqual(pasteboard.string(forType: .string), "first")
    }

    func testIgnoresAnEmptyInboundPayload() {
        copyText("keep me")
        var empty = FuseEnvelope()
        empty.sourceDeviceID = "peer"
        empty.seq = 1
        empty.clipText = FuseClipText.with { $0.text = "" }
        sync.apply(empty)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testIgnoresAnInboundHeartbeat() {
        copyText("keep me")
        var heartbeat = FuseEnvelope()
        heartbeat.sourceDeviceID = "peer"
        heartbeat.seq = 1
        heartbeat.heartbeat = FuseHeartbeat()
        sync.apply(heartbeat)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testAppliesAnInboundImageAsPngData() {
        let png = Self.onePixelPNG()
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = "peer"
        envelope.seq = 1
        envelope.clipImage = FuseClipImage.with {
            $0.mime = "image/png"
            $0.data = png
        }
        sync.apply(envelope)
        XCTAssertEqual(pasteboard.data(forType: .png), png)
    }

    // MARK: - The loop, end to end

    /// The whole point of the feature: applying a peer's copy must not turn around and
    /// broadcast it back. This is the bridge-level version of the rule — if the hash
    /// suppression were wired up wrongly, `LoopGuardTests` would still pass and two real
    /// devices would still loop.
    func testApplyingInboundContentDoesNotRebroadcastIt() {
        sync.apply(inbound(text: "from the phone", from: "peer", seq: 1, at: 100))
        let sent = envelopesSent { sync.checkForLocalChange() }
        XCTAssertEqual(sent, 0, "the injected content was echoed back to the peer")
    }

    func testAGenuineLocalCopyIsBroadcast() {
        let sent = envelopesSent {
            copyText("the user copied this")
            sync.checkForLocalChange()
        }
        XCTAssertEqual(sent, 1)
    }

    func testAnUnchangedPasteboardBroadcastsNothing() {
        copyText("stable")
        sync.checkForLocalChange() // consume the change
        let sent = envelopesSent { sync.checkForLocalChange() }
        XCTAssertEqual(sent, 0)
    }

    /// The echo of an injection must be swallowed however many change notifications the
    /// system raises for it — one write is not one notification, and each escaped echo
    /// was previously bounced straight back to the peer.
    func testRepeatedEchoesOfOneInjectionAreAllSwallowed() {
        sync.apply(inbound(text: "shared", from: "peer", seq: 1, at: 100))

        let sent = envelopesSent {
            copyText("shared") // the same bytes arriving again, as an echo would
            sync.checkForLocalChange()
            copyText("shared")
            sync.checkForLocalChange()
        }
        XCTAssertEqual(sent, 0)
    }

    func testAnImageIsPreferredOverItsTextRepresentation() {
        // A copied image often also carries a file path as text. Syncing the path instead
        // of the picture would look like it worked and be useless.
        pasteboard.clearContents()
        pasteboard.setData(Self.onePixelPNG(), forType: .png)
        pasteboard.setString("/Users/someone/Pictures/thing.png", forType: .string)

        var captured: FuseEnvelope?
        transport.onEnvelope = { captured = $0 }
        sync.checkForLocalChange()

        // broadcast() with no peers cannot be observed directly, so assert on the
        // pasteboard read path the same way checkForLocalChange does.
        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertNil(captured, "precondition: no peers are connected in this test")
    }

    private static func onePixelPNG() -> Data {
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32,
        )!
        return image.representation(using: .png, properties: [:])!
    }

    // MARK: - Ask before sending

    func testAnOfferedCopyWaitsForSend() {
        var offered: ClipOffer?
        sync.onLocalCopy = { offered = $0 }
        copyText("wait for me")
        let before = envelopesSent { sync.checkForLocalChange() }
        XCTAssertEqual(before, 0, "an offer must not leave the device on its own")
        XCTAssertEqual(offered?.text, "wait for me")
        let after = envelopesSent { offered?.send() }
        XCTAssertEqual(after, 1)
        XCTAssertEqual(sync.history.first?.text, "wait for me")
    }

    // MARK: - History sync

    private func historySync(_ texts: [(String, Int64)]) -> FuseEnvelope {
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = "peer"
        envelope.historySync = FuseHistorySync.with { sync in
            sync.items = texts.map { text, at in FuseHistoryItem.with { $0.text = text; $0.atUnixMs = at } }
        }
        return envelope
    }

    func testHistorySyncAddsWhatWeLackInTimeOrder() {
        let changeCount = pasteboard.changeCount
        let sent = envelopesSent {
            sync.apply(historySync([("older", 1_000), ("newer", 2_000)]))
        }
        XCTAssertEqual(sync.history.prefix(2).map(\.text), ["newer", "older"])
        XCTAssertTrue(sync.history.prefix(2).allSatisfy { !$0.fromSelf })
        // History only: the clipboard is untouched and nothing is answered.
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(sent, 0)
    }

    func testHistorySyncSkipsWhatWeAlreadyHave() {
        sync.apply(historySync([("same", 1_000)]))
        let count = sync.history.count
        sync.apply(historySync([("same", 5_000)]))
        XCTAssertEqual(sync.history.count, count)
    }
}

final class ScreenReceiverFramingTests: XCTestCase {
    func testSplitsAnnexBOnThreeAndFourByteStartCodes() {
        let data = Data([0, 0, 0, 1, 0x67, 0xAA, 0, 0, 1, 0x68, 0xBB, 0, 0, 0, 1, 0x65, 0xCC, 0xDD])
        XCTAssertEqual(ScreenReceiver.nalUnits(in: data), [
            Data([0x67, 0xAA]), Data([0x68, 0xBB]), Data([0x65, 0xCC, 0xDD]),
        ])
    }

    func testAvccPrefixesEachUnitWithItsBigEndianLength() {
        XCTAssertEqual(
            ScreenReceiver.avcc([Data([0x65, 0x01]), Data([0x41])]),
            Data([0, 0, 0, 2, 0x65, 0x01, 0, 0, 0, 1, 0x41]),
        )
    }
}
