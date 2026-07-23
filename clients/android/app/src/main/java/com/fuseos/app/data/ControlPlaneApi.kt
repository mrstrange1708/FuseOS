package com.fuseos.app.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.http.isSuccess

/** Authenticated control-plane client for the device registry + pairing. */
class ControlPlaneApi(
    private val client: HttpClient,
    private val baseUrl: String,
    private val tokenProvider: suspend () -> String?,
) {
    suspend fun registerDevice(request: DeviceRegisterRequest): DeviceRegisterResponse =
        post("/devices", request)

    suspend fun listDevices(selfId: String?): DeviceListResponse =
        get("/devices" + if (selfId != null) "?self=$selfId" else "")

    suspend fun initiatePairing(request: PairInitiateRequest): PairInitiateResponse =
        post("/pairing/initiate", request)

    suspend fun claimPairing(request: PairClaimRequest): PairClaimResponse =
        post("/pairing/claim", request)

    private suspend inline fun <reified B, reified R> post(path: String, body: B): R {
        val token = tokenProvider()
        val response: HttpResponse = client.post(baseUrl + path) {
            contentType(ContentType.Application.Json)
            if (token != null) header(HttpHeaders.Authorization, "Bearer $token")
            setBody(body)
        }
        return decode(response)
    }

    private suspend inline fun <reified R> get(path: String): R {
        val token = tokenProvider()
        val response: HttpResponse = client.get(baseUrl + path) {
            if (token != null) header(HttpHeaders.Authorization, "Bearer $token")
        }
        return decode(response)
    }

    private suspend inline fun <reified R> decode(response: HttpResponse): R {
        if (response.status.isSuccess()) return response.body()
        val message = try {
            response.body<ApiError>().error.message
        } catch (e: Exception) {
            "Something went wrong (${response.status.value}). Is the FuseOS server running?"
        }
        throw AuthException(message)
    }
}
