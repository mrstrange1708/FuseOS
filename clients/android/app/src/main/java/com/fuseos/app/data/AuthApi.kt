package com.fuseos.app.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
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

    /** Ends this session on the server, so the token stops working at once. Best effort:
     *  signing out locally must not wait on, or fail with, the network. */
    suspend fun signOut(token: String) {
        runCatching {
            client.post(baseUrl + "/auth/sign-out") {
                header(HttpHeaders.Authorization, "Bearer $token")
            }
        }
    }

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
