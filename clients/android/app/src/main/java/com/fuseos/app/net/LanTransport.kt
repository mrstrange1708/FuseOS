package com.fuseos.app.net

import android.os.SystemClock
import android.util.Log
import com.fuseos.app.clipboard.RoundTrip
import com.fuseos.app.core.DeviceKey
import com.fuseos.app.data.PeerPresence
import com.fuseos.app.data.SessionStore
import com.fuseos.proto.Envelope
import com.fuseos.proto.Heartbeat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * The LAN data plane: direct, encrypted, device-to-device connections to paired peers.
 *
 * Nothing here touches the control plane beyond reading presence. Clipboard and file
 * payloads travel over these sockets and are never sent to the server — that separation
 * is the architecture's central invariant.
 *
 * Discovery is signalling-provided rather than mDNS: `/signal` already relays each peer's
 * `lanAddress` and `publicKey`, which is everything needed to dial and authenticate.
 * ponytail: add mDNS (`_fuseos._tcp`) when pairing has to work without internet.
 *
 * Every device listens, but only one side dials — the lexicographically lower device id.
 * Without that tie-break both ends dial simultaneously and each pair ends up with two
 * half-used connections.
 */
class LanTransport(
    private val scope: CoroutineScope,
    private val session: SessionStore,
) {
    private val _incoming = MutableSharedFlow<Envelope>(extraBufferCapacity = 64)

    /** Envelopes received from any peer. Heartbeats are consumed here, not republished. */
    val incoming: SharedFlow<Envelope> = _incoming.asSharedFlow()

    private val _roundTrips = MutableSharedFlow<Int>(extraBufferCapacity = 8)

    /** A heartbeat's round trip, in ms, as its echo comes back (see `Heartbeat` in the proto). */
    val roundTrips: SharedFlow<Int> = _roundTrips.asSharedFlow()

    /** Heartbeats sent and not yet echoed: seq → when they went (elapsed nanos). */
    private val pings = ConcurrentHashMap<Long, Long>()

    /** When a bulk frame last finished crossing, either way (nanoTime). See [RoundTrip]. */
    @Volatile private var lastBulkAt = System.nanoTime()

    private val _connectedPeers = MutableStateFlow<Set<String>>(emptySet())

    /** Peers with a live direct channel right now — what the UI's "connected" chip reads. */
    val connectedPeers: StateFlow<Set<String>> = _connectedPeers.asStateFlow()

    private val channels = ConcurrentHashMap<String, LanChannel>()

    /** When each channel last delivered anything (elapsed ms) — how a dead link is noticed. */
    private val lastHeard = ConcurrentHashMap<LanChannel, Long>()

    private val peers = MutableStateFlow<Map<String, PeerPresence>>(emptyMap())
    private val seq = AtomicLong(0)

    /**
     * Identifies this run of the process, so a peer can tell our restarted [seq] counter
     * from a replay. Minted once per LanTransport rather than per connection: it has to
     * survive reconnects, or every dropped channel would look like a restart.
     */
    private val sessionId = java.util.UUID.randomUUID().toString()

    @Volatile private var server: ServerSocket? = null

    @Volatile private var selfDeviceId: String? = null
    private var job: Job? = null

    /** This device's netmask in bits, which decides whether a peer is on the same Wi-Fi. */
    fun lanPrefixLength(): Int? = localPrefixLength()

    /** `ip:port` to advertise over `/signal`, or null until the listener is bound. */
    fun lanAddress(): String? {
        val port = server?.localPort ?: return null
        val ip = localIpv4() ?: return null
        return "$ip:$port"
    }

    /** A new envelope stamped with this device's identity and the next sequence number. */
    fun newEnvelope(): Envelope.Builder =
        Envelope.newBuilder()
            .setSourceDeviceId(selfDeviceId.orEmpty())
            .setSeq(seq.incrementAndGet())
            .setSessionId(sessionId)
            .setSentAtUnixMs(System.currentTimeMillis())

    /**
     * Fail-soft broadcast to every connected peer (or only those in [only]); a dead channel
     * is dropped, not thrown.
     */
    fun broadcast(envelope: Envelope, only: Set<String>? = null) {
        for ((peerId, channel) in channels) {
            if (only != null && peerId !in only) continue
            try {
                channel.send(envelope)
                noteTraffic(envelope)
            } catch (e: Exception) {
                unregister(peerId, channel)
                channel.close()
            }
        }
    }

    fun start(deviceId: String, presence: StateFlow<Map<String, PeerPresence>>) {
        stop()
        selfDeviceId = deviceId
        // Bind before returning, not inside the coroutine below. The caller announces this
        // device over /signal immediately after this call, and that hello carries
        // lanAddress() — so a listener that binds a moment later means the first hello
        // advertises nothing to dial, and the peer cannot reach us until the next
        // reconnect. Binding a local socket is not a network round trip; it is cheap
        // enough to do inline, and doing it inline is what removes the race.
        val listener = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(0)) // ephemeral port
        }
        server = listener
        job = scope.launch(Dispatchers.IO) {
            try {
                coroutineScope {
                    launch { presence.collect { snapshot -> peers.value = snapshot } }
                    launch { acceptLoop(listener, deviceId) }
                    launch { dialLoop(deviceId) }
                    launch { heartbeatLoop() }
                }
            } finally {
                runCatching { listener.close() }
            }
        }
    }

    /**
     * "Connect now": dial every unlinked peer at once instead of after its backoff (up to
     * 15 s), and dial even a peer that normally dials us — its dialer may be stuck, and a
     * second channel only replaces the first (see [register]); the supervisors skip a peer
     * that has a channel, so they do not race this one. Silent on a peer offline.
     */
    fun retryNow() {
        val selfId = selfDeviceId ?: return
        scope.launch(Dispatchers.IO) {
            for ((peerId, peer) in peers.value) {
                if (channels.containsKey(peerId) || !peer.online || peer.publicKey == null) continue
                val address = peer.lanAddress ?: continue
                launch {
                    runCatching { dial(peerId, address, selfId) }
                        .onFailure { Log.w(TAG, "connect-now dial to $peerId failed: ${it.message}") }
                }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        // Blocking reads do not observe cancellation; closing the socket is what unblocks
        // them, so tear the channels down explicitly.
        channels.values.forEach { it.close() }
        channels.clear()
        runCatching { server?.close() }
        server = null
        _connectedPeers.value = emptySet()
        peers.value = emptyMap()
    }

    // MARK: - Connection lifecycle

    private suspend fun acceptLoop(listener: ServerSocket, selfId: String) = coroutineScope {
        while (currentCoroutineContext().isActive) {
            val socket = try {
                listener.accept()
            } catch (e: Exception) {
                break // listener closed, or we are shutting down
            }
            launch(Dispatchers.IO) {
                try {
                    pump(handshake(socket, selfId))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // An inbound peer whose key we do not trust lands here. Silence made
                    // "TCP connects but nothing syncs" impossible to tell from "never
                    // connected", which is exactly the case this log exists for.
                    Log.w(TAG, "inbound handshake from ${socket.inetAddress} failed: ${e.message}")
                    runCatching { socket.close() } // fail soft: a bad caller is just dropped
                }
            }
        }
    }

    /** Supervises one outbound connection per peer we are responsible for dialling. */
    private suspend fun dialLoop(selfId: String): Unit = coroutineScope {
        val supervisors = mutableMapOf<String, Job>()
        peers.collect { snapshot ->
            for (peerId in snapshot.keys) {
                if (!dialsFirst(selfId, peerId)) continue
                if (supervisors[peerId]?.isActive == true) continue
                supervisors[peerId] = launch(Dispatchers.IO) { maintain(peerId, selfId) }
            }
        }
    }

    private suspend fun maintain(peerId: String, selfId: String) {
        var backoffMs = 500L
        while (currentCoroutineContext().isActive) {
            val peer = peers.value[peerId]
            // A channel already up (an inbound one, or "Connect now"'s) needs no second dial.
            if (peer != null && peer.online && peer.lanAddress != null && peer.publicKey != null &&
                !channels.containsKey(peerId)
            ) {
                val ok = try {
                    dial(peerId, peer.lanAddress, selfId)
                    true
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Fail soft, but never silently: a dial that keeps failing is the
                    // single most common reason nothing syncs, and without this line it
                    // is invisible from outside the process.
                    Log.w(TAG, "dial to $peerId (${peer.lanAddress}) failed: ${e.message}")
                    false
                }
                backoffMs = if (ok) 500L else (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
            }
            // Event-driven: wake on the peer's details changing, and fall back to the
            // backoff so a peer that went quiet without notice is still retried.
            withTimeoutOrNull(backoffMs) {
                peers.map { it[peerId] }.distinctUntilChanged().drop(1).first()
            }
        }
    }

    private suspend fun dial(peerId: String, lanAddress: String, selfId: String) {
        val (host, port) = parseAddress(lanAddress) ?: return
        val socket = Socket()
        try {
            socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            pump(handshake(socket, selfId))
        } catch (e: Exception) {
            runCatching { socket.close() }
            throw e
        }
    }

    private suspend fun handshake(socket: Socket, selfId: String): LanChannel {
        socket.tcpNoDelay = true // latency is the product; never wait to coalesce a frame
        val keyPair = session.deviceKeyPair()
        // A peer that accepts and then says nothing must not hold a dial loop forever.
        socket.soTimeout = HANDSHAKE_TIMEOUT_MS
        return LanChannel.handshake(socket, selfId, keyPair.private) { id ->
            peers.value[id]?.publicKey?.let { runCatching { DeviceKey.decodePublic(it) }.getOrNull() }
        }.also { socket.soTimeout = 0 }
    }

    /** Blocking receive loop for one channel; returns when the connection ends. */
    private suspend fun pump(channel: LanChannel) {
        register(channel)
        // Time the link straight away rather than 15 s from now.
        ping(channel)
        try {
            while (true) {
                val envelope = channel.receive()
                lastHeard[channel] = SystemClock.elapsedRealtime()
                noteTraffic(envelope)
                if (envelope.bodyCase == Envelope.BodyCase.HEARTBEAT) {
                    echo(envelope, channel)
                } else {
                    // Suspends while a collector is behind, which stops reading the socket
                    // and lets TCP push back on the sender. `tryEmit` dropped the envelope
                    // instead: 64 file chunks queued behind a disk write, and the 65th was
                    // lost — so every file over ~4 MB failed its index check.
                    _incoming.emit(envelope)
                }
            }
        } finally {
            unregister(channel.peerDeviceId, channel)
            lastHeard.remove(channel)
            channel.close()
        }
    }

    private suspend fun heartbeatLoop() {
        while (currentCoroutineContext().isActive) {
            kotlinx.coroutines.delay(HEARTBEAT_MS)
            if (channels.isEmpty()) continue
            val now = SystemClock.elapsedRealtime()
            for (channel in channels.values) {
                // Every ping is echoed at once, so a live link is never quiet this long. A
                // peer that left the Wi-Fi without a FIN leaves the read blocked for good,
                // and writes still "succeed" into the buffer — silence is the only sign.
                // Closing ends its pump, and the dial loop reconnects.
                val heard = lastHeard.getOrPut(channel) { now }
                if (now - heard > SILENCE_LIMIT_MS) {
                    Log.w(TAG, "no word from ${channel.peerDeviceId} in ${(now - heard) / 1000} s: reconnecting")
                    channel.close()
                } else {
                    ping(channel)
                }
            }
        }
    }

    /** A heartbeat that asks to be echoed, so the link's round trip stays measured. */
    private fun ping(channel: LanChannel) {
        val envelope = newEnvelope().setHeartbeat(Heartbeat.getDefaultInstance()).build()
        pings[envelope.seq] = System.nanoTime()
        // Bounded: a peer that never echoes (an older build) must not grow this.
        if (pings.size > 16) pings.keys.minOrNull()?.let { pings.remove(it) }
        // A write that fails is how a half-open connection shows itself: close it, and
        // its pump unregisters it so the dial loop reconnects.
        runCatching { channel.send(envelope) }.onFailure { channel.close() }
    }

    private fun noteTraffic(envelope: Envelope) {
        if (RoundTrip.isBulk(envelope)) lastBulkAt = System.nanoTime()
    }

    /** The round trip since [sentAt] in ms, or null if it measured a queue, not the link. */
    fun roundTrip(sentAt: Long): Int? = RoundTrip.ms(sentAt, System.nanoTime(), lastBulkAt)

    /**
     * A ping is answered at once, on its own channel; an echo is timed and never answered.
     * A stale one is neither: it waited in a buffer while one of us slept ([RoundTrip]).
     */
    private fun echo(envelope: Envelope, channel: LanChannel) {
        val echoSeq = envelope.heartbeat.echoSeq
        if (!RoundTrip.isFresh(envelope.sentAtUnixMs)) {
            if (echoSeq != 0L) pings.remove(echoSeq)
            return
        }
        if (echoSeq == 0L) {
            runCatching { channel.send(newEnvelope().setHeartbeat(Heartbeat.newBuilder().setEchoSeq(envelope.seq)).build()) }
        } else {
            val sentAt = pings.remove(echoSeq) ?: return
            roundTrip(sentAt)?.let { _roundTrips.tryEmit(it) }
        }
    }

    private fun register(channel: LanChannel) {
        Log.i(TAG, "channel up with ${channel.peerDeviceId}")
        // A reconnect replaces the previous channel rather than racing it.
        channels.put(channel.peerDeviceId, channel)?.close()
        _connectedPeers.update { it + channel.peerDeviceId }
    }

    private fun unregister(peerId: String, channel: LanChannel) {
        if (channels.remove(peerId, channel)) {
            _connectedPeers.update { it - peerId }
        }
    }

    private companion object {
        const val TAG = "FuseLan"

        const val CONNECT_TIMEOUT_MS = 3_000
        const val HEARTBEAT_MS = 15_000L
        const val SILENCE_LIMIT_MS = 45_000L // three unanswered heartbeats
        const val HANDSHAKE_TIMEOUT_MS = 10_000
        const val MAX_BACKOFF_MS = 15_000L

        /** The lower device id dials; the higher one listens. */
        fun dialsFirst(selfId: String, peerId: String) = selfId < peerId

        fun parseAddress(value: String): Pair<String, Int>? {
            val separator = value.lastIndexOf(':')
            if (separator <= 0) return null
            val port = value.substring(separator + 1).toIntOrNull() ?: return null
            return value.substring(0, separator) to port
        }

        fun localIpv4(): String? = localInterfaceAddress()?.address?.hostAddress

        /** The netmask of [localIpv4]'s network, in bits — what "same Wi-Fi" is judged by. */
        fun localPrefixLength(): Int? = localInterfaceAddress()?.networkPrefixLength?.toInt()

        private fun localInterfaceAddress(): InterfaceAddress? =
            runCatching {
                NetworkInterface.getNetworkInterfaces()
                    .asSequence()
                    .filter { it.isUp && !it.isLoopback }
                    .flatMap { it.interfaceAddresses.asSequence() }
                    .firstOrNull { (it.address as? Inet4Address)?.isSiteLocalAddress == true }
            }.getOrNull()
    }
}
