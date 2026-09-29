package com.fuseos.app.clipboard

/**
 * How fast clips cross, measured as the round trip from sending a clip to the peer's `Ack`
 * that it applied it. A round trip because two devices' clocks cannot be trusted to agree to
 * the millisecond; it bounds the one-way time from above, so a round trip under the PRD's
 * 300 ms p95 means copy-to-available is too. Mirrors `SyncLatency` on macOS.
 */
data class SyncLatency(val lastMs: Int, val p95Ms: Int, val samples: Int)

/** The most recent samples, bounded, and their summary. */
class LatencyWindow(private val capacity: Int = 50) {
    private val samples = ArrayDeque<Int>()

    fun record(ms: Int): SyncLatency {
        samples.addLast(ms)
        while (samples.size > capacity) samples.removeFirst()
        val sorted = samples.sorted()
        // Nearest-rank p95: the smallest sample at or above 95% of the rest.
        val rank = kotlin.math.ceil(sorted.size * 0.95).toInt() - 1
        return SyncLatency(lastMs = ms, p95Ms = sorted[maxOf(0, rank)], samples = sorted.size)
    }
}

/**
 * Which round trips measure the link. Two things make one measure something else, and either
 * alone pinned the p95 at seconds, or minutes, while clips crossed in 30 ms:
 *
 * - **A side asleep.** Doze holds this app's socket reads (and a sleeping Mac holds its own)
 *   until it wakes. So a frame older than [STALE_MS] on arrival is neither answered (an echo,
 *   a clip's Ack) nor timed (an echo, an Ack) — it waited on a sleeper.
 * - **A queue.** One connection carries images, history, file chunks and screen frames; a
 *   heartbeat behind a 2 MB image times the image. A round trip counts only if no bulk frame
 *   crossed while it was in flight. Mirrors `RoundTrip` on macOS.
 */
object RoundTrip {
    // ponytail: wall clocks of two NTP-synced devices; a skew past this stops heartbeat
    // samples (none shown, never wrong ones) — send the peer's hold time if that bites.
    const val STALE_MS = 2_000L

    fun isFresh(sentAtUnixMs: Long, nowUnixMs: Long = System.currentTimeMillis()): Boolean =
        nowUnixMs - sentAtUnixMs <= STALE_MS

    /** The round trip in ms, or null when a bulk frame crossed after [sentAt] (nanoTime). */
    fun ms(sentAt: Long, now: Long, lastBulkAt: Long): Int? =
        if (lastBulkAt - sentAt < 0 && now - sentAt >= 0) ((now - sentAt) / 1_000_000).toInt() else null

    /** Envelopes big enough to queue a heartbeat behind them. */
    fun isBulk(envelope: com.fuseos.proto.Envelope): Boolean = when (envelope.bodyCase) {
        com.fuseos.proto.Envelope.BodyCase.CLIP_IMAGE,
        com.fuseos.proto.Envelope.BodyCase.HISTORY_SYNC,
        com.fuseos.proto.Envelope.BodyCase.FILE_CHUNK,
        com.fuseos.proto.Envelope.BodyCase.SCREEN_FRAME,
        com.fuseos.proto.Envelope.BodyCase.SIDECAR_FRAME,
        com.fuseos.proto.Envelope.BodyCase.MEDIA_STATE -> true
        else -> false
    }
}
