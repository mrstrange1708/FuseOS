package com.fuseos.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * These vectors are mirrored in the macOS suite (`PairingCodeTests.swift`). A code typed
 * on one platform has to normalize the same way on the other, so drift fails a test here.
 */
class PairingCodeTest {
    @Test
    fun `normalize uppercases and strips formatting`() {
        assertEquals("A7X29QKM", PairingCode.normalize("a7x2-9qkm"))
        assertEquals("A7X29QKM", PairingCode.normalize("A7X2 9QKM"))
        assertEquals("A7X29QKM", PairingCode.normalize("a7x2–9qkm"))
    }

    @Test
    fun `normalize caps at the code length so a paste cannot overflow`() {
        assertEquals("A7X29QKM", PairingCode.normalize("A7X2-9QKM-EXTRA"))
        assertEquals(PairingCode.LENGTH, PairingCode.normalize("ABCDEFGHIJ").length)
    }

    @Test
    fun `normalize keeps partial input as the user types`() {
        assertEquals("", PairingCode.normalize(""))
        assertEquals("A7X", PairingCode.normalize("a7x"))
    }

    @Test
    fun `grouped inserts the separator only once there is a second half`() {
        assertEquals("A7X2-9QKM", PairingCode.grouped("A7X29QKM"))
        assertEquals("A7X2", PairingCode.grouped("A7X2"))
        assertEquals("A7X2-9", PairingCode.grouped("A7X29"))
    }

    @Test
    fun `uri round-trips through a scan`() {
        assertEquals("fuseos://pair?code=A7X2-9QKM", PairingCode.uri("a7x29qkm"))
        assertEquals("A7X29QKM", PairingCode.fromScan(PairingCode.uri("A7X29QKM")))
    }

    @Test
    fun `fromScan accepts a bare code, with or without the separator`() {
        assertEquals("A7X29QKM", PairingCode.fromScan("A7X2-9QKM"))
        assertEquals("A7X29QKM", PairingCode.fromScan("A7X29QKM"))
        assertEquals("A7X29QKM", PairingCode.fromScan("  a7x2-9qkm\n"))
    }

    @Test
    fun `fromScan rejects any QR that is not a code`() {
        // A camera sees whatever is in front of it — a URL must not become a code by
        // having its punctuation stripped.
        assertNull(PairingCode.fromScan("https://example.com"))
        assertNull(PairingCode.fromScan("A7X2"))
        assertNull(PairingCode.fromScan("A7X2-9QKM-EXTRA"))
        assertNull(PairingCode.fromScan("fuseos://pair?code=A7X2-9QKM-EXTRA"))
        assertNull(PairingCode.fromScan("WIFI:S=home;T=WPA;P=hunter2;;"))
        assertNull(PairingCode.fromScan(""))
    }
}
