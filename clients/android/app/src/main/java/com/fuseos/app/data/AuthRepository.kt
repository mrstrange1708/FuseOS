package com.fuseos.app.data

/** Coordinates auth calls and session persistence. The UI talks only to this. */
class AuthRepository(
    private val api: AuthApi,
    private val session: SessionStore,
) {
    val tokenFlow = session.tokenFlow
    val emailFlow = session.emailFlow
    val deviceTypeFlow = session.deviceTypeFlow

    suspend fun setDeviceType(type: String) = session.saveDeviceType(type)

    suspend fun signIn(email: String, password: String) {
        val result = api.signIn(SignInRequest(email, password))
        session.save(result.token, result.user.email)
    }

    suspend fun signUp(email: String, password: String, name: String) {
        val result = api.signUp(SignUpRequest(email, password, name))
        session.save(result.token, result.user.email)
    }

    suspend fun signOut() = session.clear()
}
