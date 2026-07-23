import CryptoKit
import Foundation

/// Keeps clipboard sync from feeding itself. See `docs/protocol.md` §4 — this is the most
/// important rule in the system, because getting it wrong makes two devices ping-pong the
/// clipboard forever rather than failing visibly.
///
/// The four rules, all enforced here:
///  1. only a user-initiated local change originates an event (`shouldEmit`);
///  2. a receiver applies but never re-emits — injecting content raises a local change,
///     and that echo must be swallowed;
///  3. an event already applied is ignored, identified by (source device, seq);
///  4. conflicts resolve last-write-wins.
///
/// Sequence numbers are monotonic per source device, so tracking the highest seen per
/// source is enough for rule 3 — no growing set of identifiers.
///
/// The Android `LoopGuard` is the mirror of this file; the rules must not diverge.
struct LoopGuard {
    private let selfDeviceId: String
    private var highestSeqBySource: [String: UInt64] = [:]
    private var suppressedHash: String?
    private var lastAppliedAtMs: Int64 = 0

    init(selfDeviceId: String) {
        self.selfDeviceId = selfDeviceId
    }

    /// Whether an inbound event should be written to the local clipboard.
    ///
    /// Consumes the sequence number when it returns true, so calling it twice for the
    /// same event reports a duplicate the second time.
    mutating func shouldApply(
        sourceDeviceId: String, seq: UInt64, sentAtUnixMs: Int64,
    ) -> Bool {
        // Our own event coming back means someone re-emitted; never apply it.
        guard sourceDeviceId != selfDeviceId else { return false }

        if let highest = highestSeqBySource[sourceDeviceId], seq <= highest { return false }

        // Last-write-wins: a straggler must not overwrite newer content.
        guard sentAtUnixMs >= lastAppliedAtMs else { return false }

        highestSeqBySource[sourceDeviceId] = seq
        return true
    }

    /// Call immediately after writing inbound content to the clipboard.
    mutating func recordApplied(contentHash: String, sentAtUnixMs: Int64) {
        suppressedHash = contentHash
        lastAppliedAtMs = sentAtUnixMs
    }

    /// Whether a local clipboard change is a genuine user copy worth broadcasting.
    ///
    /// The suppression is one-shot: it swallows the echo of what we just injected, then
    /// clears, so a user deliberately re-copying that same text still syncs.
    mutating func shouldEmit(contentHash: String) -> Bool {
        if contentHash == suppressedHash {
            suppressedHash = nil
            return false
        }
        return true
    }

    /// Content identity for suppression — hashed so images cost the same as text.
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ text: String) -> String { hash(Data(text.utf8)) }
}
