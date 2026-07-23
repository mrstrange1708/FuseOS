package com.fuseos.app.data

import kotlinx.serialization.Serializable

@Serializable
data class SignUpRequest(val email: String, val password: String, val name: String)

@Serializable
data class SignInRequest(val email: String, val password: String)

@Serializable
data class AuthUser(val id: String, val email: String, val name: String? = null)

@Serializable
data class AuthResponse(val token: String, val user: AuthUser)

@Serializable
data class ApiError(val error: ApiErrorBody)

@Serializable
data class ApiErrorBody(val code: String, val message: String)

/** Thrown when the server rejects an auth request; carries a user-facing message. */
class AuthException(message: String) : Exception(message)
