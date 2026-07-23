package com.fuseos.app.data

import io.ktor.client.HttpClient
import io.ktor.client.plugins.websocket.webSocket
import io.ktor.websocket.Frame
import io.ktor.websocket.readText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * What we know about a paired peer right now.
 *
 * [publicKey] and [lanAddress] are what make a direct connection possible: the address
 * says where to dial, the key says who must answer. Both arrive from the control plane,
 * which is the only thing that can vouch for them.
 */
data class PeerPresence(
    val online: Boolean,
    val battery: Int?,
    val publicKey: String?,
    val lanAddress: String?,
)

@Serializable
private data class Hello(
    val type: String = "hello",
    val token: String,
    val deviceId: String,
    val battery: Int? = null,
    val lanAddress: String? = null,
)

@Serializable
private data class Heartbeat(
    val type: String = "heartbeat",
    val battery: Int? = null,
    val lanAddress: String? = null,
)

@Serializable
private data class SignalEvent(
    val type: String,
    val deviceId: String? = null,
    val battery: Int? = null,
    val online: Boolean? = null,
    val publicKey: String? = null,
    val lanAddress: String? = null,
    val peers: List<PeerCard>? = null,
)

@Serializable
private data class PeerCard(
    val deviceId: String,
    val battery: Int? = null,
    val online: Boolean? = null,
    val publicKey: String? = null,
    val lanAddress: String? = null,
)

/**
 * Maintains the `/signal` WebSocket: authenticates with a `hello`, sends battery
 * heartbeats, and exposes peer presence as a flow. Fail-soft — a dropped socket
 * reconnects after a short delay and never crashes the app.
 */
class SignalClient(
    private val client: HttpClient,
    private val signalUrl: String,
    private val scope: CoroutineScope,
    private val batteryProvider: () -> Int?,
    private val lanAddressProvider: () -> String? = { null },
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private val _presence = MutableStateFlow<Map<String, PeerPresence>>(emptyMap())
    val presence: StateFlow<Map<String, PeerPresence>> = _presence.asStateFlow()

    private val _paired = MutableSharedFlow<Unit>(extraBufferCapacity = 4)
    val paired: SharedFlow<Unit> = _paired.asSharedFlow()

    private var job: Job? = null

    fun start(token: String, deviceId: String) {
        stop()
        job = scope.launch { loop(token, deviceId) }
    }

    fun stop() {
        job?.cancel()
        job = null
        _presence.value = emptyMap()
    }

    private suspend fun loop(token: String, deviceId: String) {
        while (currentCoroutineContext().isActive) {
            try {
                client.webSocket(signalUrl) {
                    send(
                        Frame.Text(
                            json.encodeToString(
                                Hello(
                                    token = token,
                                    deviceId = deviceId,
                                    battery = batteryProvider(),
                                    lanAddress = lanAddressProvider(),
                                ),
                            ),
                        ),
                    )
                    val heartbeat = launch {
                        while (isActive) {
                            delay(20_000)
                            send(
                                Frame.Text(
                                    json.encodeToString(
                                        Heartbeat(
                                            battery = batteryProvider(),
                                            lanAddress = lanAddressProvider(),
                                        ),
                                    ),
                                ),
                            )
                        }
                    }
                    try {
                        for (frame in incoming) {
                            if (frame is Frame.Text) handle(frame.readText())
                        }
                    } finally {
                        heartbeat.cancel()
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // fail soft — fall through to the reconnect delay below
            }
            if (!currentCoroutineContext().isActive) break
            delay(2000)
        }
    }

    private fun handle(text: String) {
        val event = try {
            json.decodeFromString<SignalEvent>(text)
        } catch (e: Exception) {
            return
        }
        when (event.type) {
            "hello-ok" -> event.peers?.forEach {
                setPresence(it.deviceId, it.online ?: true, it.battery, it.publicKey, it.lanAddress)
            }
            "peer-online", "peer-update" -> event.deviceId?.let {
                setPresence(it, true, event.battery, event.publicKey, event.lanAddress)
            }
            // Keep the key and address on the way down: the peer is unreachable now, but
            // the details are still valid when it comes back and save a round trip.
            "peer-offline" -> event.deviceId?.let { setPresence(it, false, null, null, null) }
            "paired" -> _paired.tryEmit(Unit)
        }
    }

    private fun setPresence(
        deviceId: String,
        online: Boolean,
        battery: Int?,
        publicKey: String?,
        lanAddress: String?,
    ) {
        _presence.update { current ->
            val existing = current[deviceId]
            current + (
                deviceId to PeerPresence(
                    online = online,
                    battery = battery ?: existing?.battery,
                    publicKey = publicKey ?: existing?.publicKey,
                    lanAddress = lanAddress ?: existing?.lanAddress,
                )
                )
        }
    }
}
