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
