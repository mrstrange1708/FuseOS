package com.fuseos.app.data

import android.content.Context
import com.fuseos.app.core.Config
import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.core.DeviceInfo
import com.fuseos.app.file.FileTransfer
import com.fuseos.app.file.TransferProgress
import com.fuseos.app.file.Transfers
import com.fuseos.app.net.LanTransport
import com.fuseos.app.ui.island.ClipIsland
import com.fuseos.app.ui.island.IslandIcon
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpSend
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.plugin
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.serialization.kotlinx.json.json
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

/** Minimal manual dependency container, initialised once from [com.fuseos.app.FuseApp]. */
object ServiceLocator {

    lateinit var authRepository: AuthRepository
        private set
    lateinit var deviceRepository: DeviceRepository
        private set
    lateinit var signalClient: SignalClient
        private set
    lateinit var lanTransport: LanTransport
        private set
    lateinit var clipboardSync: ClipboardSync
        private set
    lateinit var session: SessionStore
        private set
    lateinit var connectionManager: ConnectionManager
        private set
    lateinit var clipIsland: ClipIsland
        private set
    lateinit var transfers: Transfers
        private set

    /** Outlives every screen and every service, so work that must not die with an
     *  Activity — a send fired from the island after its activity finished — runs here. */
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun init(context: Context) {
        val appContext = context.applicationContext
        val httpClient = HttpClient(OkHttp) {
            expectSuccess = false
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
            install(WebSockets)
        }
        // A phone that can't see the server fails with a raw "Connect timeout has expired
        // [url=…]" from the engine, which tells the user nothing actionable. One place
        // covers every call — auth and devices alike — because they share this client.
        httpClient.plugin(HttpSend).intercept { request ->
            try {
                execute(request)
            } catch (e: IOException) {
                throw AuthException(
                    "Can't reach the FuseOS server at ${Config.BASE_URL}. Check that it's " +
                        "running, and that the USB cable is still connected.",
                )
            }
        }
        val sessionStore = SessionStore(appContext)
        val deviceInfo = DeviceInfo(appContext)

        session = sessionStore
        authRepository = AuthRepository(AuthApi(httpClient, Config.BASE_URL), sessionStore)

        val controlPlaneApi = ControlPlaneApi(httpClient, Config.BASE_URL) { sessionStore.currentToken() }
        deviceRepository = DeviceRepository(controlPlaneApi, sessionStore, deviceInfo)

        val transport = LanTransport(appScope, sessionStore)
        lanTransport = transport
        clipboardSync = ClipboardSync(appContext, transport, appScope)
        signalClient = SignalClient(
            client = httpClient,
            signalUrl = Config.SIGNAL_URL,
            scope = appScope,
            batteryProvider = { deviceInfo.batteryPercent() },
            // The listener binds an ephemeral port, so this is null until it is up and
            // changes across restarts — hence a provider rather than a fixed value.
            lanAddressProvider = { transport.lanAddress() },
        )
        val island = ClipIsland(appContext)
        clipIsland = island
        // A copy asks before it travels. With no overlay permission there is nowhere to
        // ask, so it travels — losing the prompt should not lose the sync.
        clipboardSync.onLocalCopy = { clip ->
            if (island.canDraw()) {
                island.prompt(clip) { clipboardSync.send(it) }
            } else {
                clipboardSync.send(clip)
            }
        }
        // Files are received into app storage and moved to Downloads once verified, so a
        // half-written file is never visible there. Collected on IO: every chunk is a
        // disk write.
        val transfer = FileTransfer(
            directory = File(appContext.filesDir, "received"),
            newEnvelope = { transport.newEnvelope() },
            emit = { transport.broadcast(it) },
        )
        transfers = Transfers(appContext, transfer, transport, appScope).apply {
            // The island says what happened to a file, the same way it does for a clip.
            // Without overlay permission the notification and the app's list still do.
            onFinished = { p ->
                // A cancel is the user's own doing; announcing it back to them is noise.
                if (island.canDraw() && p.state != TransferProgress.State.Cancelled) {
                    val done = p.state == TransferProgress.State.Done
                    island.status(
                        title = when {
                            !done -> "File didn't go through"
                            p.outgoing -> "Sent to your Mac"
                            else -> "File from your Mac"
                        },
                        subtitle = p.name,
                        icon = if (p.outgoing) IslandIcon.Sent else IslandIcon.Incoming,
                    )
                }
            }
        }
        appScope.launch(Dispatchers.IO) { transport.incoming.collect { transfer.receive(it) } }
        appScope.launch(Dispatchers.IO) { transport.connectedPeers.collect { transfer.onPeersChanged(it) } }

        connectionManager = ConnectionManager(
            deviceRepository, signalClient, sessionStore, transport, clipboardSync,
        )
    }
}
