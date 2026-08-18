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
/// Sequence numbers are monotonic per source device *within one session*: they restart at
/// zero whenever that device's process does, which on Android is constant. So the highest
/// seq is tracked per (source, session), and a new session id resets it. Without that, a
/// peer restarting looked exactly like a replay, and every clip it sent afterwards was
/// dropped until this side restarted too.
///
/// The Android `LoopGuard` is the mirror of this file; the rules must not diverge.
struct LoopGuard {
    /// The peer's session and how far its counter has got within it.
    private struct SourceState {
        var sessionId: String
        var highestSeq: UInt64
    }

    private let selfDeviceId: String
    private var bySource: [String: SourceState] = [:]
    private var suppressedHash: String?
    private var suppressedAt: Date = .distantPast
    private var lastAppliedAtMs: Int64 = 0

    init(selfDeviceId: String) {
        self.selfDeviceId = selfDeviceId
    }

    /// Whether an inbound event should be written to the local clipboard.
    ///
    /// Consumes the sequence number when it returns true, so calling it twice for the
    /// same event reports a duplicate the second time.
    mutating func shouldApply(
        sourceDeviceId: String, sessionId: String, seq: UInt64, sentAtUnixMs: Int64,
    ) -> Bool {
        // Our own event coming back means someone re-emitted; never apply it.
        guard sourceDeviceId != selfDeviceId else { return false }

        if let seen = bySource[sourceDeviceId], seen.sessionId == sessionId {
            // Same session, so the counter is comparable and this is a replay or straggler.
            guard seq > seen.highestSeq else { return false }
        }
        // A different session id means the peer restarted; its counter began again and
        // nothing we remember about the old one applies.

        // Last-write-wins: a straggler must not overwrite newer content.
        guard sentAtUnixMs >= lastAppliedAtMs else { return false }

        bySource[sourceDeviceId] = SourceState(sessionId: sessionId, highestSeq: seq)
        return true
    }

    /// Call immediately after writing inbound content to the clipboard.
    mutating func recordApplied(contentHash: String, sentAtUnixMs: Int64, now: Date = Date()) {
        suppressedHash = contentHash
        suppressedAt = now
        lastAppliedAtMs = sentAtUnixMs
    }

    /// Whether a local clipboard change is a genuine user copy worth broadcasting.
    ///
    /// Suppression covers a short window rather than a single call. Writing the clipboard
    /// can raise several change notifications rather than one — pronounced on Android,
    /// where a one-shot guard turned a single inbound clip into four local copies, each
    /// bounced back to the peer. The rule is mirrored here so the two clients agree.
    ///
    /// The window is what a user loses: re-copying byte-identical content within
    /// `suppressWindow` does not sync. That costs nothing — the peer already holds exactly
    /// those bytes, so the event would be a no-op even if it went.
    mutating func shouldEmit(contentHash: String, now: Date = Date()) -> Bool {
        if contentHash == suppressedHash, now.timeIntervalSince(suppressedAt) < Self.suppressWindow {
            return false
        }
        return true
    }

    /// Long enough to cover the burst of change notifications one write produces, short
    /// enough that it cannot swallow a deliberate re-copy the user would notice.
    static let suppressWindow: TimeInterval = 3

    /// Content identity for suppression — hashed so images cost the same as text.
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ text: String) -> String { hash(Data(text.utf8)) }
}
