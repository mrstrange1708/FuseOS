package com.fuseos.app.data

import kotlinx.coroutines.withTimeoutOrNull

/** Coordinates auth calls and session persistence. The UI talks only to this. */
class AuthRepository(
    private val api: AuthApi,
    private val session: SessionStore,
) {
    val tokenFlow = session.tokenFlow
    val emailFlow = session.emailFlow
    val deviceNameFlow = session.deviceNameFlow
    val connectDoneFlow = session.connectDoneFlow

    suspend fun setDeviceName(name: String) = session.saveDeviceName(name)

    suspend fun signIn(email: String, password: String) {
        val result = api.signIn(SignInRequest(email, password))
        session.save(result.token, result.user.email)
    }

    suspend fun signUp(email: String, password: String, name: String) {
        val result = api.signUp(SignUpRequest(email, password, name))
        session.save(result.token, result.user.email)
    }

    /** Ends the session on the server (best effort, a few seconds at most), then here. */
    suspend fun signOut() {
        session.currentToken()?.let { token -> withTimeoutOrNull(3_000) { api.signOut(token) } }
        session.clear()
    }
}
