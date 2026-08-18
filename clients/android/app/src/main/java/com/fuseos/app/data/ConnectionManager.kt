package com.fuseos.app.data

import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.net.LanTransport
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Brings this device's connection stack up exactly once, from wherever it is first needed.
 *
 * Three entry points race for this — the dashboard on launch, the foreground service on
 * boot-of-process, and a Share-sheet send that may be the only thing running — and none of
 * them can assume another got there first. The mutex makes them queue behind one attempt
 * instead of registering the device three times.
 *
 * A failed attempt stores nothing, so the next caller retries the whole thing. That matters
 * because the very first attempt happens when the server may simply be unreachable; giving
 * up once left the app insisting this device wasn't registered until a force-quit.
 */
class ConnectionManager(
    private val repo: DeviceRepository,
    private val signal: SignalClient,
    private val session: SessionStore,
    private val transport: LanTransport,
    private val clipboard: ClipboardSync,
) {
    private val lock = Mutex()

    @Volatile
    private var deviceId: String? = null

    /** This device's server id, registering and starting the LAN + signal stack if needed. */
    suspend fun ensureStarted(): String = lock.withLock {
        deviceId?.let { return@withLock it }
        // Idempotent server-side, and it refreshes this device's battery and lastSeen.
        val id = repo.registerThisDevice()
        // Bring the listener up before saying hello, so the very first hello can already
        // carry a lanAddress for peers to dial.
        transport.start(id, signal.presence)
        clipboard.start(id)
        session.currentToken()?.let { token -> signal.start(token, id) }
        deviceId = id
        id
    }

    /** Tears the stack down on sign-out; the next [ensureStarted] rebuilds it. */
    suspend fun stop() = lock.withLock {
        signal.stop()
        clipboard.stop()
        transport.stop()
        deviceId = null
    }
}
