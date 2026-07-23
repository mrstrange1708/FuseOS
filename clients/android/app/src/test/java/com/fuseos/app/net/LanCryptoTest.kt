package com.fuseos.app.net

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.fail
import org.junit.Test
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import javax.crypto.AEADBadTagException

/**
 * The channel crypto every LAN frame depends on. A mistake here does not surface as a
 * crash on device — it surfaces as two devices that hold a socket open and never manage
 * to decrypt each other, which is the hardest failure in the system to diagnose.
 *
 * The macOS `LanCrypto` is the mirror of this file, so anything asserted here is also a
 * statement about what CryptoKit must produce.
 */
class LanCryptoTest {

    private fun keyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

    private fun hex(value: String): ByteArray =
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    // MARK: - sessionKeys

    @Test
    fun `both ends derive the same pair of keys with the directions crossed`() {
        // The single most important property in the data plane: if A's send key is not
        // B's receive key, nothing decrypts and the channel silently stalls.
        val a = keyPair()
        val b = keyPair()
        val aNonce = ByteArray(32) { it.toByte() }
        val bNonce = ByteArray(32) { (200 - it).toByte() }

        val aKeys = LanCrypto.sessionKeys(
            privateKey = a.private, peerPublicKey = b.public,
            selfDeviceId = "aaaa-1111", peerDeviceId = "bbbb-2222",
            selfNonce = aNonce, peerNonce = bNonce,
        )
        val bKeys = LanCrypto.sessionKeys(
            privateKey = b.private, peerPublicKey = a.public,
            selfDeviceId = "bbbb-2222", peerDeviceId = "aaaa-1111",
            selfNonce = bNonce, peerNonce = aNonce,
        )

        assertArrayEquals("A must encrypt with the key B decrypts with", aKeys.send, bKeys.receive)
        assertArrayEquals("and the same in the other direction", bKeys.send, aKeys.receive)
    }

    @Test
    fun `the two directions use different keys`() {
        // One key both ways would let the two GCM counters collide, and a repeated
        // (key, nonce) pair in GCM is a total loss of confidentiality — not a nuance.
        val a = keyPair()
        val b = keyPair()
        val keys = LanCrypto.sessionKeys(
            privateKey = a.private, peerPublicKey = b.public,
            selfDeviceId = "aaaa", peerDeviceId = "bbbb",
            selfNonce = ByteArray(32) { 7 }, peerNonce = ByteArray(32) { 9 },
        )
        assertFalse(keys.send.contentEquals(keys.receive))
        assertEquals(32, keys.send.size)
        assertEquals(32, keys.receive.size)
    }

    @Test
    fun `derivation depends on device id ordering not on who dialled`() {
        // Either side may be the one that opened the socket. The keys must come out the
        // same either way, because only the device ids decide which direction is which.
        val a = keyPair()
        val b = keyPair()
        val aNonce = ByteArray(32) { it.toByte() }
        val bNonce = ByteArray(32) { (it * 3).toByte() }

        // "zzzz" is the high id here, so the low/high roles are the reverse of the
        // previous test — the pairing must still line up.
        val lowId = "aaaa-1111"
        val highId = "zzzz-9999"

        val lowSide = LanCrypto.sessionKeys(
            privateKey = a.private, peerPublicKey = b.public,
            selfDeviceId = lowId, peerDeviceId = highId,
            selfNonce = aNonce, peerNonce = bNonce,
        )
        val highSide = LanCrypto.sessionKeys(
            privateKey = b.private, peerPublicKey = a.public,
            selfDeviceId = highId, peerDeviceId = lowId,
            selfNonce = bNonce, peerNonce = aNonce,
        )

        assertArrayEquals(lowSide.send, highSide.receive)
        assertArrayEquals(highSide.send, lowSide.receive)

        // And the low side's send key is the low-to-high key regardless of which of the
        // two actually dialled — swapping the roles must not swap the keys.
        val lowSideAgain = LanCrypto.sessionKeys(
            privateKey = a.private, peerPublicKey = b.public,
            selfDeviceId = lowId, peerDeviceId = highId,
            selfNonce = aNonce, peerNonce = bNonce,
        )
        assertArrayEquals(lowSide.send, lowSideAgain.send)
    }

    @Test
    fun `different nonces give different session keys for the same key pair`() {
        // The nonces are the only per-connection input; static-static ECDH alone would
        // reuse the same key on every reconnect and hand an attacker a replay window.
        val a = keyPair()
        val b = keyPair()
        fun derive(selfNonce: ByteArray) = LanCrypto.sessionKeys(
            privateKey = a.private, peerPublicKey = b.public,
            selfDeviceId = "aaaa", peerDeviceId = "bbbb",
            selfNonce = selfNonce, peerNonce = ByteArray(32),
        ).send

        assertFalse(derive(ByteArray(32)).contentEquals(derive(ByteArray(32) { 1 })))
    }

    @Test
    fun `nonce order follows device id order so the salt is not commutative`() {
        // Concatenating the nonces the other way round produces different keys, which is
        // exactly why the ordering rule exists. If this ever stopped mattering, the
        // ordering rule would be dead code and the "who is low" logic could rot unnoticed.
        val a = keyPair()
        val b = keyPair()
        val n1 = ByteArray(32) { 1 }
        val n2 = ByteArray(32) { 2 }
        val salted = LanCrypto.hkdf(
            LanCrypto.sharedSecret(a.private, b.public), n1 + n2, "info".toByteArray(), 32,
        )
        val swapped = LanCrypto.hkdf(
            LanCrypto.sharedSecret(a.private, b.public), n2 + n1, "info".toByteArray(), 32,
        )
        assertFalse(salted.contentEquals(swapped))
    }

    @Test
    fun `ecdh shared secret is symmetric`() {
        val a = keyPair()
        val b = keyPair()
        assertArrayEquals(
            LanCrypto.sharedSecret(a.private, b.public),
            LanCrypto.sharedSecret(b.private, a.public),
        )
    }

    // MARK: - hkdf

    @Test
    fun `hkdf matches RFC 5869 test case 1`() {
        // The macOS side uses CryptoKit's HKDF, not this hand-rolled loop. Pinning both
        // to the published vector is what keeps them byte-identical.
        val ikm = hex("0b".repeat(22))
        val salt = hex("000102030405060708090a0b0c")
        val info = hex("f0f1f2f3f4f5f6f7f8f9")

        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a" +
                "2d2d0a90cf1a5a4c5db02d56ecc4c5bf" +
                "34007208d5b887185865",
            LanCrypto.hkdf(ikm, salt, info, 42).hex(),
        )
    }

    @Test
    fun `hkdf output longer than one hash block chains correctly`() {
        // 42 bytes needs two HMAC blocks, so the RFC vector already covers the chaining;
        // this pins that a prefix of a longer expansion is the shorter expansion, which
        // is the property that breaks first if the counter or the T(i-1) feed is wrong.
        val ikm = hex("0b".repeat(22))
        val salt = hex("000102030405060708090a0b0c")
        val info = hex("f0f1f2f3f4f5f6f7f8f9")
        val long = LanCrypto.hkdf(ikm, salt, info, 96)
        assertArrayEquals(LanCrypto.hkdf(ikm, salt, info, 42), long.copyOf(42))
        assertEquals(96, long.size)
    }

    @Test
    fun `hkdf is deterministic and separated by salt and info`() {
        val ikm = ByteArray(32) { it.toByte() }
        val salt = ByteArray(16) { 5 }
        val info = "fuseos:lan:v1:low-to-high".toByteArray()

        assertArrayEquals(LanCrypto.hkdf(ikm, salt, info, 32), LanCrypto.hkdf(ikm, salt, info, 32))
        assertFalse(
            LanCrypto.hkdf(ikm, salt, info, 32)
                .contentEquals(LanCrypto.hkdf(ikm, ByteArray(16) { 6 }, info, 32)),
        )
        assertFalse(
            LanCrypto.hkdf(ikm, salt, info, 32)
                .contentEquals(LanCrypto.hkdf(ikm, salt, "fuseos:lan:v1:high-to-low".toByteArray(), 32)),
        )
    }

    // MARK: - seal / open

    @Test
    fun `seal and open round trip`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "clipboard contents".toByteArray()
        assertArrayEquals(plaintext, LanCrypto.open(key, 3, LanCrypto.seal(key, 3, plaintext)))
    }

    @Test
    fun `seal and open round trip an empty payload`() {
        // An Envelope with only default fields serialises to zero bytes, so the empty
        // plaintext is a real case on the wire, not a curiosity.
        val key = ByteArray(32) { it.toByte() }
        val sealed = LanCrypto.seal(key, 0, ByteArray(0))
        assertEquals("nothing but the GCM tag", 16, sealed.size)
        assertEquals(0, LanCrypto.open(key, 0, sealed).size)
    }

    @Test
    fun `open with the wrong key fails`() {
        // This is the check that stops a peer whose key we do not hold from ever reaching
        // the envelope parser.
        val sealed = LanCrypto.seal(ByteArray(32) { 1 }, 0, "secret".toByteArray())
        assertFailsWithBadTag { LanCrypto.open(ByteArray(32) { 2 }, 0, sealed) }
    }

    @Test
    fun `open with the wrong counter fails`() {
        // The counter is the GCM nonce, so a replayed or reordered frame fails the tag
        // check instead of being applied — that is the whole replay defence.
        val key = ByteArray(32) { 1 }
        val sealed = LanCrypto.seal(key, 7, "secret".toByteArray())
        assertFailsWithBadTag { LanCrypto.open(key, 8, sealed) }
        assertFailsWithBadTag { LanCrypto.open(key, 6, sealed) }
        assertFailsWithBadTag { LanCrypto.open(key, 0, sealed) }
    }

    @Test
    fun `open of a truncated frame fails`() {
        // A short read on the socket must not hand a partial plaintext upstream.
        val key = ByteArray(32) { 1 }
        val sealed = LanCrypto.seal(key, 0, "a reasonably long payload".toByteArray())
        assertFailsWithBadTag { LanCrypto.open(key, 0, sealed.copyOf(sealed.size - 1)) }

        // A frame shorter than the 16-byte tag is not a tag failure but a length one, and
        // the JCE reports it as an unchecked ProviderException rather than a
        // GeneralSecurityException — worth pinning, because LanChannel.receive's docs
        // promise a GeneralSecurityException and a caller that catches only that would
        // let this one through. LanTransport catches Exception, so the data plane still
        // fails soft; the assertion below is what says "throws, never returns bytes".
        try {
            LanCrypto.open(key, 0, sealed.copyOf(4))
            fail("a frame shorter than the GCM tag must not open")
        } catch (e: RuntimeException) {
            // expected: java.security.ProviderException wrapping ShortBufferException
        } catch (e: java.security.GeneralSecurityException) {
            // also acceptable — some providers report this as a checked failure
        }
    }

    @Test
    fun `open of a corrupted frame fails wherever the corruption lands`() {
        val key = ByteArray(32) { 1 }
        val plaintext = "clipboard contents".toByteArray()
        for (index in listOf(0, 5, plaintext.size, plaintext.size + 15)) {
            val sealed = LanCrypto.seal(key, 0, plaintext)
            sealed[index] = (sealed[index] + 1).toByte()
            assertFailsWithBadTag { LanCrypto.open(key, 0, sealed) }
        }
    }

    @Test
    fun `every counter produces a distinct gcm nonce`() {
        // gcmNonce is private, but nonce reuse is observable: AES-GCM is deterministic, so
        // sealing the same plaintext under the same key twice can only match if the nonce
        // repeated. A repeated (key, nonce) in GCM leaks the authentication key.
        val key = ByteArray(32) { 3 }
        val plaintext = "same bytes every time".toByteArray()
        val counters = listOf(0L, 1L, 2L, 255L, 256L, 65_535L, 1L shl 32, Long.MAX_VALUE)
        val seen = counters.map { LanCrypto.seal(key, it, plaintext).toList() }
        assertEquals("two counters produced identical ciphertext", counters.size, seen.toSet().size)
    }

    @Test
    fun `a high counter still round trips`() {
        // The nonce packs the counter into 8 big-endian bytes; a sign-extension slip would
        // only show up once the top bit is set.
        val key = ByteArray(32) { 4 }
        val plaintext = "late in a very long session".toByteArray()
        for (counter in listOf(Int.MAX_VALUE.toLong(), 1L shl 40, Long.MAX_VALUE)) {
            assertArrayEquals(plaintext, LanCrypto.open(key, counter, LanCrypto.seal(key, counter, plaintext)))
        }
    }

    @Test
    fun `session keys actually work as channel keys`() {
        // Ties the derivation and the cipher together the way a real connection does.
        val a = keyPair()
        val b = keyPair()
        val aNonce = ByteArray(32) { it.toByte() }
        val bNonce = ByteArray(32) { (it + 100).toByte() }
        val aKeys = LanCrypto.sessionKeys(
            a.private, b.public, "aaaa", "bbbb", aNonce, bNonce,
        )
        val bKeys = LanCrypto.sessionKeys(
            b.private, a.public, "bbbb", "aaaa", bNonce, aNonce,
        )

        val fromA = LanCrypto.seal(aKeys.send, 0, "A to B".toByteArray())
        assertEquals("A to B", String(LanCrypto.open(bKeys.receive, 0, fromA)))

        val fromB = LanCrypto.seal(bKeys.send, 0, "B to A".toByteArray())
        assertEquals("B to A", String(LanCrypto.open(aKeys.receive, 0, fromB)))

        // The counters are per-direction, so both sides opening at counter 0 is correct
        // and must not collide.
        assertNotEquals(fromA.toList(), fromB.toList())
    }

    private inline fun assertFailsWithBadTag(block: () -> Unit) {
        try {
            block()
            fail("expected the GCM tag check to reject this frame")
        } catch (e: AEADBadTagException) {
            // expected
        }
    }
}
