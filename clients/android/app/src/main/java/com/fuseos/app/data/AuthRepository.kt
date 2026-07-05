package com.fuseos.app.data

/** Coordinates auth calls and session persistence. The UI talks only to this. */
class AuthRepository(
    private val api: AuthApi,
    private val session: SessionStore,
) {
    val tokenFlow = session.tokenFlow
    val emailFlow = session.emailFlow

    suspend fun signIn(email: String, password: String) {
        val result = api.signIn(SignInRequest(email, password))
        session.save(result.token, result.user.email)
    }

    suspend fun signUp(email: String, password: String, name: String?) {
        val result = api.signUp(SignUpRequest(email, password, name?.ifBlank { null }))
        session.save(result.token, result.user.email)
    }

    suspend fun signOut() = session.clear()
}
