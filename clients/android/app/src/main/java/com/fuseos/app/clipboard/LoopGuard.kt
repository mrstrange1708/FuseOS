package com.fuseos.app.clipboard

import java.security.MessageDigest

/**
 * Keeps clipboard sync from feeding itself. See `docs/protocol.md` §4 — this is the most
 * important rule in the system, because getting it wrong makes two devices ping-pong the
 * clipboard forever rather than failing visibly.
 *
 * The four rules, all enforced here:
 *  1. only a user-initiated local change originates an event ([shouldEmit]);
 *  2. a receiver applies but never re-emits — injecting content raises a local change
 *     notification, and that echo must be swallowed;
 *  3. an event already applied is ignored, identified by (source device, seq);
 *  4. conflicts resolve last-write-wins.
 *
 * Sequence numbers are monotonic per source device *within one session*: they restart at
 * zero whenever that device's process does, which on Android is constant. So the highest
 * seq is tracked per (source, session), and a new session id resets it.
 *
 * Not thread-safe; callers serialise access (one clipboard, one owner).
 */
class LoopGuard(private val selfDeviceId: String) {

    /** The peer's session and how far its counter has got within it. */
    private data class SourceState(val sessionId: String, val highestSeq: Long)

    private val bySource = mutableMapOf<String, SourceState>()
    private var suppressedHash: String? = null
    private var suppressedAtMs = 0L
    private var lastAppliedAtMs = 0L

    /**
     * Whether an inbound event should be written to the local clipboard.
     *
     * Consumes the sequence number when it returns true, so calling it twice for the same
     * event reports a duplicate the second time.
     */
    fun shouldApply(
        sourceDeviceId: String,
        sessionId: String,
        seq: Long,
        sentAtUnixMs: Long,
    ): Boolean {
        // Our own event coming back means someone re-emitted; never apply it.
        if (sourceDeviceId == selfDeviceId) return false

        // `seq` is uint64 on the wire but Long here, so anything at or above 2^63 arrives
        // negative. A signed comparison would read it as older than everything — and once
        // a large value was accepted, nothing from that device would ever apply again.
        // Compare unsigned, matching the proto type and the macOS client's UInt64.
        val seen = bySource[sourceDeviceId]
        if (seen != null && seen.sessionId == sessionId) {
            // Same session, so the counter is comparable and this is a replay or straggler.
            if (java.lang.Long.compareUnsigned(seq, seen.highestSeq) <= 0) return false
        }
        // A different session id means the peer restarted; its counter began again and
        // nothing we remember about the old one applies.

        // Last-write-wins: a straggler must not overwrite newer content.
        if (sentAtUnixMs < lastAppliedAtMs) return false

        bySource[sourceDeviceId] = SourceState(sessionId, seq)
        return true
    }

    /** Call immediately after writing inbound content to the clipboard. */
    fun recordApplied(contentHash: String, sentAtUnixMs: Long, nowMs: Long = System.currentTimeMillis()) {
        suppressedHash = contentHash
        suppressedAtMs = nowMs
        lastAppliedAtMs = sentAtUnixMs
    }

    /**
     * Whether a local clipboard change is a genuine user copy worth broadcasting.
     *
     * Suppression covers a short window rather than a single call. Writing the clipboard
     * raises *several* change notifications on Android, not one, so a one-shot guard
     * swallowed the first echo and re-broadcast the rest — one inbound clip came back as
     * four local copies, each bounced to the peer again.
     *
     * The window is what a user loses: re-copying byte-identical content within
     * [SUPPRESS_WINDOW_MS] does not sync. That costs nothing — the peer already holds
     * exactly those bytes, so the event would be a no-op even if it went.
     */
    fun shouldEmit(contentHash: String, nowMs: Long = System.currentTimeMillis()): Boolean {
        if (contentHash == suppressedHash && nowMs - suppressedAtMs < SUPPRESS_WINDOW_MS) {
            return false
        }
        return true
    }

    companion object {
        /**
         * How long an injected clip stays suppressed. Long enough to cover the burst of
         * change notifications one `setPrimaryClip` produces, short enough that it cannot
         * swallow a deliberate re-copy the user would notice.
         */
        const val SUPPRESS_WINDOW_MS = 3_000L

        /** Content identity for suppression — hashed so images cost the same as text. */
        fun hash(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") { "%02x".format(it) }

        fun hash(text: String): String = hash(text.toByteArray(Charsets.UTF_8))
    }
}
