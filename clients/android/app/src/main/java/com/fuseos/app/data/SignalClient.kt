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
 * What we know about a peer right now.
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
    /** The peer's name as the server last announced it; null until one has been. */
    val name: String? = null,
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
private data class RelayOut(
    val type: String = "relay",
    val to: String,
    val stream: String,
    val data: String? = null,
    val close: Boolean? = null,
)

/** A piece of a relayed channel from [from] (docs/protocol.md §19): sealed bytes, or the end. */
class RelayIn(val from: String, val stream: String, val data: ByteArray?, val close: Boolean)

@Serializable
private data class SignalEvent(
    val type: String,
    val from: String? = null,
    val stream: String? = null,
    val data: String? = null,
    val close: Boolean? = null,
    val deviceId: String? = null,
    val battery: Int? = null,
    val online: Boolean? = null,
    val publicKey: String? = null,
    val lanAddress: String? = null,
    val name: String? = null,
    val peers: List<PeerCard>? = null,
)

@Serializable
private data class PeerCard(
    val deviceId: String,
    val battery: Int? = null,
    val online: Boolean? = null,
    val publicKey: String? = null,
    val lanAddress: String? = null,
    val name: String? = null,
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


    private var job: Job? = null

    /** The live socket's outbox; null between connections, so nothing stale is replayed. */
    @Volatile private var outbox: kotlinx.coroutines.channels.Channel<String>? = null

    private val _relay = kotlinx.coroutines.flow.MutableSharedFlow<RelayIn>(extraBufferCapacity = 256)

    /** Relayed channel pieces from this account's other devices, in order. */
    val relay: kotlinx.coroutines.flow.SharedFlow<RelayIn> = _relay

    /** Sends a piece of a relayed channel; false when there is no live socket to send it on. */
    fun sendRelay(to: String, stream: String, data: ByteArray?, close: Boolean = false): Boolean {
        val box = outbox ?: return false
        val encoded = data?.let { android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP) }
        return box.trySend(json.encodeToString(RelayOut(to = to, stream = stream, data = encoded, close = close.takeIf { it }))).isSuccess
    }

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
                    val box = kotlinx.coroutines.channels.Channel<String>(capacity = 256)
                    outbox = box
                    val sender = launch { for (message in box) send(Frame.Text(message)) }
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
                        outbox = null
                        box.close()
                        sender.cancel()
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

    private suspend fun handle(text: String) {
        val event = try {
            json.decodeFromString<SignalEvent>(text)
        } catch (e: Exception) {
            return
        }
        when (event.type) {
            "relay" -> {
                val from = event.from ?: return
                val stream = event.stream ?: return
                val bytes = event.data?.let { runCatching { android.util.Base64.decode(it, android.util.Base64.NO_WRAP) }.getOrNull() }
                _relay.emit(RelayIn(from, stream, bytes, event.close == true))
            }
            "hello-ok" -> event.peers?.forEach {
                setPresence(it.deviceId, it.online ?: true, it.battery, it.publicKey, it.lanAddress, it.name)
            }
            "peer-online", "peer-update" -> event.deviceId?.let {
                setPresence(it, true, event.battery, event.publicKey, event.lanAddress, event.name)
            }
            // Keep the key and address on the way down: the peer is unreachable now, but
            // the details are still valid when it comes back and save a round trip.
            "peer-offline" -> event.deviceId?.let { setPresence(it, false, null, null, null) }
        }
    }

    private fun setPresence(
        deviceId: String,
        online: Boolean,
        battery: Int?,
        publicKey: String?,
        lanAddress: String?,
        name: String? = null,
    ) {
        _presence.update { current ->
            val existing = current[deviceId]
            current + (
                deviceId to PeerPresence(
                    online = online,
                    battery = battery ?: existing?.battery,
                    publicKey = publicKey ?: existing?.publicKey,
                    lanAddress = lanAddress ?: existing?.lanAddress,
                    name = name ?: existing?.name,
                )
                )
        }
    }
}
