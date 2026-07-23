package com.fuseos.app.net

import java.security.PrivateKey
import java.security.PublicKey
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Channel crypto for the LAN data plane. The macOS `LanCrypto` is the mirror of this
 * file; the two must derive identical keys or no device can talk to the other.
 *
 * Both ends already hold the other's P-256 public key, vouched for by the control plane
 * at pairing time. ECDH over those static keys yields a shared secret, and the two fresh
 * per-connection nonces exchanged in the handshake salt it into session keys — one per
 * direction, so the GCM counters on the two sides can never collide.
 *
 * ponytail: static-static ECDH has no forward secrecy — a stolen device key decrypts any
 * recorded session. The upgrade is ephemeral keys plus signatures (Noise IK), skipped
 * because it costs a full handshake protocol to defend against an attacker who already
 * has the device.
 */
object LanCrypto {
    const val NONCE_LEN = 32
    private const val GCM_TAG_BITS = 128
    private const val HMAC = "HmacSHA256"

    /** Info strings are direction-specific; see [sessionKeys]. */
    private val INFO_LOW_TO_HIGH = "fuseos:lan:v1:low-to-high".toByteArray()
    private val INFO_HIGH_TO_LOW = "fuseos:lan:v1:high-to-low".toByteArray()

    /** The two directional keys for a connection, from this device's point of view. */
    data class SessionKeys(val send: ByteArray, val receive: ByteArray)

    /**
     * Derives this connection's keys.
     *
     * Ordering is by device id rather than by who dialed, so both ends independently
     * agree on which nonce comes first and which key is theirs without exchanging
     * anything more.
     */
    fun sessionKeys(
        privateKey: PrivateKey,
        peerPublicKey: PublicKey,
        selfDeviceId: String,
        peerDeviceId: String,
        selfNonce: ByteArray,
        peerNonce: ByteArray,
    ): SessionKeys {
        val selfIsLow = selfDeviceId < peerDeviceId
        val salt = if (selfIsLow) selfNonce + peerNonce else peerNonce + selfNonce
        val secret = sharedSecret(privateKey, peerPublicKey)
        val lowToHigh = hkdf(secret, salt, INFO_LOW_TO_HIGH, 32)
        val highToLow = hkdf(secret, salt, INFO_HIGH_TO_LOW, 32)
        secret.fill(0)
        return if (selfIsLow) {
            SessionKeys(send = lowToHigh, receive = highToLow)
        } else {
            SessionKeys(send = highToLow, receive = lowToHigh)
        }
    }

    fun sharedSecret(privateKey: PrivateKey, peerPublicKey: PublicKey): ByteArray =
        KeyAgreement.getInstance("ECDH").apply {
            init(privateKey)
            doPhase(peerPublicKey, true)
        }.generateSecret()

    /**
     * RFC 5869 HKDF-SHA256. The JDK ships no HKDF; CryptoKit's `hkdfDerivedSymmetricKey`
     * on the macOS side is the same construction, so this must stay byte-exact.
     */
    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val mac = Mac.getInstance(HMAC)

        mac.init(SecretKeySpec(salt, HMAC))
        val prk = mac.doFinal(ikm)

        mac.init(SecretKeySpec(prk, HMAC))
        val out = ByteArray(length)
        var block = ByteArray(0)
        var written = 0
        var counter = 1
        while (written < length) {
            mac.update(block)
            mac.update(info)
            mac.update(counter.toByte())
            block = mac.doFinal()
            val take = minOf(block.size, length - written)
            block.copyInto(out, written, 0, take)
            written += take
            counter++
        }
        return out
    }

    fun seal(key: ByteArray, counter: Long, plaintext: ByteArray): ByteArray =
        cipher(Cipher.ENCRYPT_MODE, key, counter).doFinal(plaintext)

    /** Throws [javax.crypto.AEADBadTagException] if the frame was tampered with or reordered. */
    fun open(key: ByteArray, counter: Long, ciphertext: ByteArray): ByteArray =
        cipher(Cipher.DECRYPT_MODE, key, counter).doFinal(ciphertext)

    private fun cipher(mode: Int, key: ByteArray, counter: Long): Cipher =
        Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(GCM_TAG_BITS, gcmNonce(counter)))
        }

    /** 12-byte GCM nonce: a big-endian frame counter in the low 8 bytes. Safe to start at
     *  zero because the keys are fresh per connection. */
    private fun gcmNonce(counter: Long): ByteArray {
        val nonce = ByteArray(12)
        for (i in 0 until 8) {
            nonce[11 - i] = ((counter shr (8 * i)) and 0xff).toByte()
        }
        return nonce
    }
}
