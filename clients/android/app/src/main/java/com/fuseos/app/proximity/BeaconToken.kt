package com.fuseos.app.proximity

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The Bluetooth beacon value: HMAC-SHA256(key, window) cut to 8 bytes, the window being
 * unix time in ten-minute steps as an 8-byte big-endian integer. Must match `BeaconToken`
 * on macOS byte for byte (shared vector in both test suites).
 */
object BeaconToken {
    const val WINDOW_MS = 600_000L

    fun window(nowMs: Long): Long = nowMs / WINDOW_MS

    fun token(key: ByteArray, window: Long): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(ByteBuffer.allocate(8).putLong(window).array()).copyOf(8)
    }
}
