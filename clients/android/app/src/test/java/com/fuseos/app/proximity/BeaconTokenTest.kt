package com.fuseos.app.proximity

import org.junit.Assert.assertEquals
import org.junit.Test

class BeaconTokenTest {
    /** The same vector as macOS's BeaconTokenTests — the two must agree byte for byte. */
    @Test fun matchesTheSharedVector() {
        val key = ByteArray(16) { it.toByte() }
        val hex = BeaconToken.token(key, 2_900_000).joinToString("") { "%02x".format(it) }
        assertEquals("007dc1e4d2402c5a", hex)
    }
}
