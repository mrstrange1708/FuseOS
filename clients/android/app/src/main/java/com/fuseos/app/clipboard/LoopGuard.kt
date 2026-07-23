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
 * Sequence numbers are monotonic per source device, so tracking the highest seen per
 * source is enough for rule 3 — no growing set of identifiers.
 *
 * Not thread-safe; callers serialise access (one clipboard, one owner).
 */
class LoopGuard(private val selfDeviceId: String) {

    private val highestSeqBySource = mutableMapOf<String, Long>()
    private var suppressedHash: String? = null
    private var lastAppliedAtMs = 0L

    /**
     * Whether an inbound event should be written to the local clipboard.
     *
     * Consumes the sequence number when it returns true, so calling it twice for the same
     * event reports a duplicate the second time.
     */
    fun shouldApply(sourceDeviceId: String, seq: Long, sentAtUnixMs: Long): Boolean {
        // Our own event coming back means someone re-emitted; never apply it.
        if (sourceDeviceId == selfDeviceId) return false

        // `seq` is uint64 on the wire but Long here, so anything at or above 2^63 arrives
        // negative. A signed comparison would read it as older than everything — and once
        // a large value was accepted, nothing from that device would ever apply again.
        // Compare unsigned, matching the proto type and the macOS client's UInt64.
        val highest = highestSeqBySource[sourceDeviceId]
        if (highest != null && java.lang.Long.compareUnsigned(seq, highest) <= 0) return false

        // Last-write-wins: a straggler must not overwrite newer content.
        if (sentAtUnixMs < lastAppliedAtMs) return false

        highestSeqBySource[sourceDeviceId] = seq
        return true
    }

    /** Call immediately after writing inbound content to the clipboard. */
    fun recordApplied(contentHash: String, sentAtUnixMs: Long) {
        suppressedHash = contentHash
        lastAppliedAtMs = sentAtUnixMs
    }

    /**
     * Whether a local clipboard change is a genuine user copy worth broadcasting.
     *
     * The suppression is one-shot: it swallows the echo of what we just injected, then
     * clears, so a user deliberately re-copying that same text still syncs.
     */
    fun shouldEmit(contentHash: String): Boolean {
        if (contentHash == suppressedHash) {
            suppressedHash = null
            return false
        }
        return true
    }

    companion object {
        /** Content identity for suppression — hashed so images cost the same as text. */
        fun hash(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") { "%02x".format(it) }

        fun hash(text: String): String = hash(text.toByteArray(Charsets.UTF_8))
    }
}
