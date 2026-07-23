package com.fuseos.app.clipboard

import org.junit.Assert.assertFalse
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
        assertTrue(guard().shouldApply("peer", seq = 1, sentAtUnixMs = 100))
    }

    @Test
    fun `never applies an event we originated`() {
        // The echo of our own copy coming back is the first half of a sync loop.
        assertFalse(guard().shouldApply("self", seq = 1, sentAtUnixMs = 100))
    }

    @Test
    fun `ignores a replayed or duplicated sequence number`() {
        val guard = guard()
        assertTrue(guard.shouldApply("peer", seq = 5, sentAtUnixMs = 100))
        assertFalse(guard.shouldApply("peer", seq = 5, sentAtUnixMs = 100))
        assertFalse(guard.shouldApply("peer", seq = 4, sentAtUnixMs = 100))
        assertTrue(guard.shouldApply("peer", seq = 6, sentAtUnixMs = 101))
    }

    @Test
    fun `tracks sequence numbers per source device`() {
        val guard = guard()
        assertTrue(guard.shouldApply("peer-a", seq = 9, sentAtUnixMs = 100))
        // A different device's low sequence number is not a duplicate.
        assertTrue(guard.shouldApply("peer-b", seq = 1, sentAtUnixMs = 100))
    }

    @Test
    fun `a straggler does not overwrite newer content`() {
        val guard = guard()
        assertTrue(guard.shouldApply("peer", seq = 1, sentAtUnixMs = 500))
        guard.recordApplied(LoopGuard.hash("newer"), sentAtUnixMs = 500)
        assertFalse(guard.shouldApply("peer", seq = 2, sentAtUnixMs = 400))
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

    @Test
    fun `suppression is one-shot so a deliberate re-copy still syncs`() {
        val guard = guard()
        val text = "shared text"
        guard.recordApplied(LoopGuard.hash(text), sentAtUnixMs = 100)

        assertFalse(guard.shouldEmit(LoopGuard.hash(text))) // the injection's own echo
        assertTrue(guard.shouldEmit(LoopGuard.hash(text))) // the user copying it again
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

        assertTrue(deviceB.shouldApply("A", seq = 1, sentAtUnixMs = 100)) // B: applies
        deviceB.recordApplied(hash, sentAtUnixMs = 100)

        assertFalse(deviceB.shouldEmit(hash)) // B: echo suppressed — the loop ends here
    }
}
