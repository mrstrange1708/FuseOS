package com.fuseos.app.clipboard

import com.fuseos.proto.ClipImage
import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import com.fuseos.proto.Heartbeat
import com.fuseos.proto.ScreenFrame
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

/** Same cases as `RoundTripTests` on macOS. */
class RoundTripTest {
    @Test fun aFrameThatWaitedOnASleeperIsStale() {
        assertTrue(RoundTrip.isFresh(sentAtUnixMs = 10_000, nowUnixMs = 12_000))
        assertFalse(RoundTrip.isFresh(sentAtUnixMs = 10_000, nowUnixMs = 12_001))
        // A peer clock a little ahead is still fresh.
        assertTrue(RoundTrip.isFresh(sentAtUnixMs = 10_500, nowUnixMs = 10_000))
    }

    @Test fun aRoundTripThatABulkFrameCrossedMeasuredAQueue() {
        assertEquals(30, RoundTrip.ms(sentAt = 5_000_000_000, now = 5_030_000_000, lastBulkAt = 4_000_000_000))
        assertNull(RoundTrip.ms(sentAt = 5_000_000_000, now = 6_400_000_000, lastBulkAt = 5_000_000_001))
        assertNull(RoundTrip.ms(sentAt = 5_000_000_000, now = 5_030_000_000, lastBulkAt = 5_000_000_000))
    }

    @Test fun imagesAndFramesAreBulkButTextAndHeartbeatsAreNot() {
        assertTrue(RoundTrip.isBulk(Envelope.newBuilder().setClipImage(ClipImage.getDefaultInstance()).build()))
        assertTrue(RoundTrip.isBulk(Envelope.newBuilder().setScreenFrame(ScreenFrame.getDefaultInstance()).build()))
        assertFalse(RoundTrip.isBulk(Envelope.newBuilder().setClipText(ClipText.getDefaultInstance()).build()))
        assertFalse(RoundTrip.isBulk(Envelope.newBuilder().setHeartbeat(Heartbeat.getDefaultInstance()).build()))
    }
}
