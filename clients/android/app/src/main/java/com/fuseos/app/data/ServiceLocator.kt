package com.fuseos.app.data

import android.content.Context
import com.fuseos.app.core.Config
import com.fuseos.app.clipboard.ClipboardSync
import com.fuseos.app.core.DeviceInfo
import com.fuseos.app.net.LanTransport
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpSend
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.plugin
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.serialization.kotlinx.json.json
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

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
        // covers every call — auth, devices, pairing — because they share this client.
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
        connectionManager = ConnectionManager(
            deviceRepository, signalClient, sessionStore, transport, clipboardSync,
        )
    }
}
