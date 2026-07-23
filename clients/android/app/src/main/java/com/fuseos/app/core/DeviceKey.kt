package com.fuseos.app.core

import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec

/**
 * This device's long-lived P-256 identity.
 *
 * The public key is registered as `devices.public_key`, reaches peers on the `/signal`
 * peer card, and is what both ends authenticate during the LAN handshake — ECDH against
 * it derives the channel key. This keypair is the entire basis of trust between two
 * paired devices.
 *
 * Public keys cross platforms, so they travel as base64 **SPKI DER**: the encoding that
 * both `PublicKey.getEncoded()` here and CryptoKit's `derRepresentation` on macOS emit
 * for the same key. Private keys never leave their device, so each platform keeps them
 * in whatever encoding is native (PKCS#8 here, raw scalar on macOS).
 *
 * P-256 rather than X25519 because `KeyAgreement("ECDH")` works from API 11, while XDH
 * needs API 33 and minSdk here is 26.
 */
object DeviceKey {

    fun generate(): KeyPair =
        KeyPairGenerator.getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()

    fun encodePrivate(key: PrivateKey): String = key.encoded.b64()

    fun decodePrivate(encoded: String): PrivateKey =
        KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(encoded.unB64()))

    fun encodePublic(key: PublicKey): String = key.encoded.b64()

    fun decodePublic(encoded: String): PublicKey =
        KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(encoded.unB64()))

    private fun ByteArray.b64(): String = Base64.encodeToString(this, Base64.NO_WRAP)

    private fun String.unB64(): ByteArray = Base64.decode(this, Base64.NO_WRAP)
}
