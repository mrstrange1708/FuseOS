package com.fuseos.app.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.fuseos.app.core.DeviceKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.security.KeyPair

private val Context.authDataStore by preferencesDataStore(name = "fuse_session")

/**
 * Persists the signed-in session (token + email), the chosen device type, and
 * this install's stable device identity (key + server device id) via DataStore.
 *
 * Dev note: for production, the token belongs in EncryptedSharedPreferences /
 * the Android Keystore, not plaintext DataStore.
 */
class SessionStore(private val context: Context) {

    private object Keys {
        val TOKEN = stringPreferencesKey("token")
        val EMAIL = stringPreferencesKey("email")
        val DEVICE_NAME = stringPreferencesKey("device_name")
        val DEVICE_ID = stringPreferencesKey("device_id")
        val CONNECT_DONE = booleanPreferencesKey("connect_done")

        // Deliberately not the old "device_key": that held a random stand-in in a
        // different format, and a fresh name lets stale installs re-register cleanly
        // instead of presenting a key nothing can do ECDH against.
        val DEVICE_PUBLIC_KEY = stringPreferencesKey("device_public_key")
        val DEVICE_PRIVATE_KEY = stringPreferencesKey("device_private_key")
    }

    /** Guards the read-then-generate below; two racing callers must not mint two identities. */
    private val keyMutex = Mutex()

    val tokenFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.TOKEN] }
    val emailFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.EMAIL] }
    /**
     * What the user called this phone. Null until they have been through naming, which is
     * also what routes them there. Stored locally because `POST /devices` upserts the name
     * on every launch — sending the detected name each time would overwrite their choice.
     */
    val deviceNameFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.DEVICE_NAME] }
    val deviceIdFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.DEVICE_ID] }

    /** Whether the user has been through the connect screen once. */
    val connectDoneFlow: Flow<Boolean> = context.authDataStore.data.map { it[Keys.CONNECT_DONE] == true }

    suspend fun markConnectDone() {
        context.authDataStore.edit { it[Keys.CONNECT_DONE] = true }
    }

    suspend fun save(token: String, email: String) {
        context.authDataStore.edit {
            it[Keys.TOKEN] = token
            it[Keys.EMAIL] = email
        }
    }

    suspend fun saveDeviceName(name: String) {
        context.authDataStore.edit { it[Keys.DEVICE_NAME] = name }
    }

    suspend fun currentDeviceName(): String? = deviceNameFlow.first()

    suspend fun saveDeviceId(id: String) {
        context.authDataStore.edit { it[Keys.DEVICE_ID] = id }
    }

    suspend fun currentToken(): String? = tokenFlow.first()

    /**
     * This device's P-256 identity, minted on first use and then reused forever.
     *
     * ponytail: the private key sits in DataStore beside the session token rather than
     * behind the Android Keystore, because Keystore ECDH (`PURPOSE_AGREE_KEY`) needs
     * API 31 and minSdk here is 26. Both secrets should move together — either raise
     * minSdk to 31, or put both behind EncryptedSharedPreferences.
     */
    suspend fun deviceKeyPair(): KeyPair = keyMutex.withLock {
        val prefs = context.authDataStore.data.first()
        val stored = prefs[Keys.DEVICE_PRIVATE_KEY] to prefs[Keys.DEVICE_PUBLIC_KEY]
        val (privateKey, publicKey) = stored
        if (privateKey != null && publicKey != null) {
            return@withLock KeyPair(DeviceKey.decodePublic(publicKey), DeviceKey.decodePrivate(privateKey))
        }
        val pair = DeviceKey.generate()
        context.authDataStore.edit {
            it[Keys.DEVICE_PRIVATE_KEY] = DeviceKey.encodePrivate(pair.private)
            it[Keys.DEVICE_PUBLIC_KEY] = DeviceKey.encodePublic(pair.public)
        }
        pair
    }

    /** This device's public key as base64 SPKI DER — the `publicKey` the API expects. */
    suspend fun deviceKey(): String = DeviceKey.encodePublic(deviceKeyPair().public)

    /**
     * Drops this device's identity so the next [deviceKeyPair] mints a fresh one.
     *
     * Only for the one case the server can't resolve for us: the key is already
     * registered to a *different* account (`public_key_taken`), which happens on a phone
     * that signed in with another account before. Rotating is safe — it only ever
     * discards our own private half — and the stale row stays with its old owner.
     */
    suspend fun resetDeviceKey() = keyMutex.withLock {
        context.authDataStore.edit {
            it.remove(Keys.DEVICE_PRIVATE_KEY)
            it.remove(Keys.DEVICE_PUBLIC_KEY)
        }
        Unit
    }

    /** Signs out. Keeps the device keypair (the physical device identity) but drops the
     *  session and the per-account server device id. */
    suspend fun clear() {
        context.authDataStore.edit {
            it.remove(Keys.TOKEN)
            it.remove(Keys.EMAIL)
            it.remove(Keys.DEVICE_NAME)
            it.remove(Keys.DEVICE_ID)
            it.remove(Keys.CONNECT_DONE)
        }
    }
}
