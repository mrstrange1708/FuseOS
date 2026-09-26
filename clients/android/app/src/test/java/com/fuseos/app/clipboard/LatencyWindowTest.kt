package com.fuseos.app.clipboard

import org.junit.Assert.assertEquals
import org.junit.Test

/** Same cases as `LatencyWindowTests` on macOS — the two report the same numbers. */
class LatencyWindowTest {
    @Test fun p95IsTheNearestRankAndTheWindowIsBounded() {
        val window = LatencyWindow(capacity = 20)
        var last: SyncLatency? = null
        for (ms in 1..40) last = window.record(ms)
        // Only 21..40 remain; the 95th percentile of 20 samples is the 19th.
        assertEquals(SyncLatency(lastMs = 40, p95Ms = 39, samples = 20), last)
    }

    @Test fun oneSampleIsItsOwnPercentile() {
        assertEquals(SyncLatency(5, 5, 1), LatencyWindow().record(5))
    }
}
