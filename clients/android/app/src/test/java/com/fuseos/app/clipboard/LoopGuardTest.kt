package com.fuseos.app.clipboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The loop-prevention rules from `docs/protocol.md` §4. A regression here does not throw;
 * it makes two real devices overwrite each other's clipboard in a loop, which is why
 * these cases are pinned down in-process.
 */
class LoopGuardTest {

    private fun guard() = LoopGuard(selfDeviceId = "self")

    @Test
    fun `applies a fresh event from a peer`() {
        assertTrue(guard().shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 100))
    }

    @Test
    fun `never applies an event we originated`() {
        // The echo of our own copy coming back is the first half of a sync loop.
        assertFalse(guard().shouldApply("self", sessionId = "s1", seq = 1, sentAtUnixMs = 100))
    }

    @Test
    fun `ignores a replayed or duplicated sequence number`() {
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 5, sentAtUnixMs = 100))
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = 5, sentAtUnixMs = 100))
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = 4, sentAtUnixMs = 100))
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 6, sentAtUnixMs = 101))
    }

    @Test
    fun `tracks sequence numbers per source device`() {
        val guard = guard()
        assertTrue(guard.shouldApply("peer-a", sessionId = "s1", seq = 9, sentAtUnixMs = 100))
        // A different device's low sequence number is not a duplicate.
        assertTrue(guard.shouldApply("peer-b", sessionId = "s1", seq = 1, sentAtUnixMs = 100))
    }

    @Test
    fun `a straggler does not overwrite newer content`() {
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 500))
        guard.recordApplied(LoopGuard.hash("newer"), sentAtUnixMs = 500)
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = 2, sentAtUnixMs = 400))
    }

    @Test
    fun `swallows the echo of content it just injected`() {
        val guard = guard()
        val text = "copied on the Mac"
        guard.recordApplied(LoopGuard.hash(text), sentAtUnixMs = 100)

        // Writing the clipboard raises a local change notification; re-emitting it is
        // the second half of a sync loop.
        assertFalse(guard.shouldEmit(LoopGuard.hash(text)))
    }

    /**
     * `setPrimaryClip` raises several change notifications, not one, so suppression has to
     * cover a window. A one-shot guard swallowed the first echo and re-emitted the rest —
     * observed on a real phone as one inbound clip becoming four local copies, each
     * bounced back to the Mac.
     */
    @Test
    fun `suppression covers the whole burst of echoes`() {
        val guard = guard()
        val text = "shared text"
        guard.recordApplied(LoopGuard.hash(text), sentAtUnixMs = 100, nowMs = 1_000)

        for (delay in listOf(0L, 50L, 400L, 2_900L)) {
            assertFalse(
                "echo at +${delay}ms must not be re-emitted",
                guard.shouldEmit(LoopGuard.hash(text), nowMs = 1_000 + delay),
            )
        }
    }

    /**
     * Past the window a deliberate re-copy syncs again — the suppression is a burst
     * filter, not a permanent block on that content.
     */
    @Test
    fun `a deliberate re-copy after the window still syncs`() {
        val guard = guard()
        val text = "shared text"
        guard.recordApplied(LoopGuard.hash(text), sentAtUnixMs = 100, nowMs = 1_000)
        assertFalse(guard.shouldEmit(LoopGuard.hash(text), nowMs = 1_000))
        assertTrue(
            guard.shouldEmit(
                LoopGuard.hash(text),
                nowMs = 1_000 + LoopGuard.SUPPRESS_WINDOW_MS + 1,
            ),
        )
    }

    @Test
    fun `emits unrelated local copies`() {
        val guard = guard()
        guard.recordApplied(LoopGuard.hash("from peer"), sentAtUnixMs = 100)
        assertTrue(guard.shouldEmit(LoopGuard.hash("something the user copied")))
    }

    @Test
    fun `a full round trip between two devices settles instead of looping`() {
        // Mirrors what happens on real hardware: A copies, B applies, B's clipboard
        // listener fires, and B must not send it back.
        val deviceA = LoopGuard("A")
        val deviceB = LoopGuard("B")
        val text = "hello"
        val hash = LoopGuard.hash(text)

        assertTrue(deviceA.shouldEmit(hash)) // A: user copies

        assertTrue(deviceB.shouldApply("A", sessionId = "s1", seq = 1, sentAtUnixMs = 100)) // B: applies
        deviceB.recordApplied(hash, sentAtUnixMs = 100)

        assertFalse(deviceB.shouldEmit(hash)) // B: echo suppressed — the loop ends here
    }

    // MARK: - Sequence numbers

    @Test
    fun `a very large sequence number is accepted`() {
        // seq is uint64 on the wire but Long in Kotlin, so anything at or above 2^63
        // arrives as a negative number. Nothing legitimate ever gets near this — a real
        // counter starts at 0 and increments per copy — but the comparison must not
        // misbehave on the values a peer can actually put on the wire.
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = Long.MAX_VALUE - 1, sentAtUnixMs = 100))
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = Long.MAX_VALUE, sentAtUnixMs = 101))
    }

    @Test
    fun `sequence numbers are ordered unsigned, matching the wire type`() {
        // seq is uint64 in the proto but Long here, so anything at or above 2^63 arrives
        // negative. Compared signed it would look older than everything, and once a large
        // value had been accepted nothing from that device would ever apply again — one
        // malformed envelope would kill that peer's clipboard until an app restart.
        //
        // Unreachable by an honest peer (both clients count up from 0), so this is
        // hardening. It also keeps the comparison identical to the macOS client, which
        // holds seq as a UInt64 and is unsigned for free.
        val guard = guard()
        // 2^63 as a uint64 arrives as Long.MIN_VALUE, and is genuinely LARGER than 1.
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 100))
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = Long.MIN_VALUE, sentAtUnixMs = 101))
        // …and having accepted it, ordinary numbers below it are correctly stale.
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = 2, sentAtUnixMs = 102))

        // The top of the unsigned range is uint64 max (-1L), above Long.MIN_VALUE.
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = -1L, sentAtUnixMs = 103))
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = Long.MIN_VALUE, sentAtUnixMs = 104))
    }

    @Test
    fun `a gap in sequence numbers does not block later events`() {
        // Frames are dropped on a fail-soft data plane, so the receiver sees holes. It
        // must move on, not wait for the missing number.
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 100))
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 9, sentAtUnixMs = 101))
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = 5, sentAtUnixMs = 102)) // the late arrival
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 10, sentAtUnixMs = 103))
    }

    // MARK: - Last-write-wins boundary

    @Test
    fun `an event from the same millisecond as the last applied one still applies`() {
        // The comparison is strictly less-than, so equal timestamps pass. Deliberate:
        // millisecond resolution collides easily and two copies inside one tick must not
        // silently drop the second. The tie is then broken by the sequence number.
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 500))
        guard.recordApplied(LoopGuard.hash("first"), sentAtUnixMs = 500)
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 2, sentAtUnixMs = 500))
    }

    @Test
    fun `one millisecond older is rejected`() {
        // The other side of the same boundary — pinning both is what stops a refactor
        // from flipping < to <= without anyone noticing.
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 500))
        guard.recordApplied(LoopGuard.hash("first"), sentAtUnixMs = 500)
        assertFalse(guard.shouldApply("peer", sessionId = "s1", seq = 2, sentAtUnixMs = 499))
    }

    @Test
    fun `the timestamp gate only engages once something has been applied`() {
        // recordApplied is what arms last-write-wins. An event that was never written to
        // the clipboard must not shift the watermark, or a duplicate would raise the bar
        // for everyone.
        val guard = guard()
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 1, sentAtUnixMs = 9_000))
        // No recordApplied — e.g. the payload turned out to be empty and was dropped.
        assertTrue(guard.shouldApply("peer", sessionId = "s1", seq = 2, sentAtUnixMs = 5))
    }

    // MARK: - Multiple peers

    @Test
    fun `interleaved events from two peers do not consume each other's sequence numbers`() {
        // Three paired devices is the ordinary case once a user adds a second Mac. Each
        // source has its own counter, so B's seq 1 must not be shadowed by A's seq 7.
        val guard = guard()
        assertTrue(guard.shouldApply("peer-a", sessionId = "s1", seq = 1, sentAtUnixMs = 100))
        assertTrue(guard.shouldApply("peer-b", sessionId = "s1", seq = 1, sentAtUnixMs = 101))
        assertTrue(guard.shouldApply("peer-a", sessionId = "s1", seq = 2, sentAtUnixMs = 102))
        assertFalse(guard.shouldApply("peer-b", sessionId = "s1", seq = 1, sentAtUnixMs = 103)) // b's own replay
        assertTrue(guard.shouldApply("peer-b", sessionId = "s1", seq = 2, sentAtUnixMs = 104))
        assertFalse(guard.shouldApply("peer-a", sessionId = "s1", seq = 2, sentAtUnixMs = 105)) // a's own replay
    }

    @Test
    fun `last-write-wins is global across peers, so a lagging clock loses`() {
        // KNOWN BEHAVIOUR, pinned deliberately. The timestamp watermark is one value for
        // the whole guard, not one per source, and sent_at_unix_ms is the *sender's* wall
        // clock. A peer running a few seconds behind therefore has its copies ignored
        // until the watermark catches up.
        //
        // That is what "last-write-wins by sent_at_unix_ms" means (docs/protocol.md §4.4)
        // and it is right for the two-device case this guards. Worth knowing before a
        // third device with a skewed clock joins.
        val guard = guard()
        assertTrue(guard.shouldApply("fast-clock", sessionId = "s1", seq = 1, sentAtUnixMs = 10_000))
        guard.recordApplied(LoopGuard.hash("from the fast device"), sentAtUnixMs = 10_000)
        assertFalse(guard.shouldApply("slow-clock", sessionId = "s1", seq = 1, sentAtUnixMs = 9_000))
    }

    @Test
    fun `an event we originated is refused whatever its sequence number`() {
        // Rule 2 has to win over everything else; a re-emitted event of ours carries a
        // perfectly plausible seq and timestamp and would otherwise look fresh.
        val guard = guard()
        assertFalse(guard.shouldApply("self", sessionId = "s1", seq = 1, sentAtUnixMs = Long.MAX_VALUE))
        assertFalse(guard.shouldApply("self", sessionId = "s1", seq = Long.MAX_VALUE, sentAtUnixMs = 1))
        // …and it must not have consumed a sequence number on the way through: a real
        // peer that happens to be called "self" is a different device id entirely.
        assertTrue(guard.shouldApply("selfish", sessionId = "s1", seq = 1, sentAtUnixMs = 1))
    }

    // MARK: - Content hashing

    @Test
    fun `hash matches the published SHA-256 vectors`() {
        // Both clients hash the same bytes to decide whether an inbound clip is the echo
        // of one they just applied, so the digest and its hex encoding are part of the
        // contract, not an implementation detail. The "abc" vector covers bytes above
        // 0x7f, which is where a sloppy hex encoder produces "ffffffbf" instead of "bf".
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            LoopGuard.hash(""),
        )
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            LoopGuard.hash("abc"),
        )
        assertEquals(64, LoopGuard.hash(ByteArray(1024) { 0xff.toByte() }).length)
    }

    @Test
    fun `hash is stable across calls and distinct across content`() {
        // Suppression is keyed on this string. A hash that varied between calls would
        // never suppress anything (endless loop); one that collided would swallow a
        // genuine user copy.
        assertEquals(LoopGuard.hash("same text"), LoopGuard.hash("same text"))
        assertNotEquals(LoopGuard.hash("some text"), LoopGuard.hash("same text"))
        assertNotEquals(LoopGuard.hash(""), LoopGuard.hash(" "))
        assertNotEquals(
            LoopGuard.hash(ByteArray(4) { 0 }),
            LoopGuard.hash(ByteArray(5) { 0 }),
        )
        // The String overload must agree with the byte overload, or a text clip and the
        // same clip arriving as bytes would suppress differently.
        assertEquals(LoopGuard.hash("héllo"), LoopGuard.hash("héllo".toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun `suppression distinguishes content that only differs late in the payload`() {
        // Two screenshots of the same window differ in a handful of bytes. Truncating the
        // hash, or hashing only a prefix, would make the second one un-emittable.
        val guard = guard()
        val first = ByteArray(64 * 1024) { 1 }
        val second = first.copyOf().also { it[it.size - 1] = 2 }
        guard.recordApplied(LoopGuard.hash(first), sentAtUnixMs = 100)
        assertTrue(guard.shouldEmit(LoopGuard.hash(second)))
    }

    /**
     * The bug this pins: `seq` restarts at zero when the peer's process does, but this
     * side keeps running and remembers the old high-water mark. Before session ids, a peer
     * restart made every later clip from it invisible until this side restarted too — and
     * Android kills apps constantly, so that was most of the time.
     */
    @Test
    fun `peer restarting its sequence counter still applies`() {
        val guard = guard()
        assertTrue(guard.shouldApply("phone", "s1", 7, 1_000))

        // Phone restarts: new session, counter back to 1.
        assertTrue(guard.shouldApply("phone", "s2", 1, 2_000))
        assertTrue(guard.shouldApply("phone", "s2", 2, 3_000))
    }

    /**
     * A new session must not become a hole in replay protection: within the new session
     * the counter is tracked from scratch, and duplicates there are still rejected.
     */
    @Test
    fun `replay protection restarts with the new session`() {
        val guard = guard()
        assertTrue(guard.shouldApply("phone", "s1", 7, 1_000))
        assertTrue(guard.shouldApply("phone", "s2", 1, 2_000))
        assertFalse(guard.shouldApply("phone", "s2", 1, 3_000))
    }
}
