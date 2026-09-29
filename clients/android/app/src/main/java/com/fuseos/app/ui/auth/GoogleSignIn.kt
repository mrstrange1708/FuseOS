package com.fuseos.app.ui.auth

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.fuseos.app.core.Config
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

/**
 * Asks the system for a Google account and returns its ID token, or null if the user
 * backed out. The token's audience is the web client ([Config.GOOGLE_WEB_CLIENT_ID]),
 * which is what the server verifies; Google recognises this app by its package and
 * signing certificate (the Android clients in the Google Cloud project).
 *
 * [context] must be an Activity: the account picker is shown over it.
 */
suspend fun googleIdToken(context: Context): String? {
    val option = GetGoogleIdOption.Builder()
        .setServerClientId(Config.GOOGLE_WEB_CLIENT_ID)
        .setFilterByAuthorizedAccounts(false)
        .build()
    val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
    return try {
        val credential = CredentialManager.create(context).getCredential(context, request).credential
        GoogleIdTokenCredential.createFrom(credential.data).idToken
    } catch (e: GetCredentialCancellationException) {
        null
    } catch (e: NoCredentialException) {
        throw IllegalStateException("Add a Google account to this phone first (Settings → Accounts).")
    }
}
