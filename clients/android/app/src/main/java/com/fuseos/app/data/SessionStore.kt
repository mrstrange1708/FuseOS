package com.fuseos.app.data

import android.content.Context
import android.util.Base64
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.security.SecureRandom

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
        val DEVICE_TYPE = stringPreferencesKey("device_type")
        val DEVICE_ID = stringPreferencesKey("device_id")
        val DEVICE_KEY = stringPreferencesKey("device_key")
    }

    val tokenFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.TOKEN] }
    val emailFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.EMAIL] }
    val deviceTypeFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.DEVICE_TYPE] }
    val deviceIdFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.DEVICE_ID] }

    suspend fun save(token: String, email: String) {
        context.authDataStore.edit {
            it[Keys.TOKEN] = token
            it[Keys.EMAIL] = email
        }
    }

    suspend fun saveDeviceType(type: String) {
        context.authDataStore.edit { it[Keys.DEVICE_TYPE] = type }
    }

    suspend fun saveDeviceId(id: String) {
        context.authDataStore.edit { it[Keys.DEVICE_ID] = id }
    }

    suspend fun currentToken(): String? = tokenFlow.first()

    /**
     * Stable per-install identifier used as the device's public key (a random
     * stand-in until the LAN data plane brings real keypairs). Generated once.
     */
    suspend fun deviceKey(): String {
        context.authDataStore.data.first()[Keys.DEVICE_KEY]?.let { return it }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val key = Base64.encodeToString(bytes, Base64.NO_WRAP)
        context.authDataStore.edit { it[Keys.DEVICE_KEY] = key }
        return key
    }

    /** Signs out. Keeps `device_key` (the physical device identity) but drops the
     *  session and the per-account server device id. */
    suspend fun clear() {
        context.authDataStore.edit {
            it.remove(Keys.TOKEN)
            it.remove(Keys.EMAIL)
            it.remove(Keys.DEVICE_TYPE)
            it.remove(Keys.DEVICE_ID)
        }
    }
}
