package com.fuseos.app.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.authDataStore by preferencesDataStore(name = "fuse_session")

/**
 * Persists the signed-in session (token + email) via DataStore.
 *
 * Dev note: for production, the token belongs in EncryptedSharedPreferences /
 * the Android Keystore, not plaintext DataStore.
 */
class SessionStore(private val context: Context) {

    private object Keys {
        val TOKEN = stringPreferencesKey("token")
        val EMAIL = stringPreferencesKey("email")
    }

    val tokenFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.TOKEN] }
    val emailFlow: Flow<String?> = context.authDataStore.data.map { it[Keys.EMAIL] }

    suspend fun save(token: String, email: String) {
        context.authDataStore.edit {
            it[Keys.TOKEN] = token
            it[Keys.EMAIL] = email
        }
    }

    suspend fun clear() {
        context.authDataStore.edit { it.clear() }
    }
}
