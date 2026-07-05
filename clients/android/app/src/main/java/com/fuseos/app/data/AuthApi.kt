package com.fuseos.app.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.http.isSuccess

/** Thin HTTP client for the control-plane auth endpoints (see docs/api.md). */
class AuthApi(
    private val client: HttpClient,
    private val baseUrl: String,
) {
    suspend fun signUp(request: SignUpRequest): AuthResponse =
        post("/auth/sign-up/email", request)

    suspend fun signIn(request: SignInRequest): AuthResponse =
        post("/auth/sign-in/email", request)

    private suspend inline fun <reified T> post(path: String, body: T): AuthResponse {
        val response: HttpResponse = client.post(baseUrl + path) {
            contentType(ContentType.Application.Json)
            setBody(body)
        }
        if (response.status.isSuccess()) {
            return response.body()
        }
        val message = try {
            response.body<ApiError>().error.message
        } catch (e: Exception) {
            "Something went wrong (${response.status.value}). Is the FuseOS server running?"
        }
        throw AuthException(message)
    }
}
