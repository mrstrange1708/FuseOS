package com.fuseos.app.data

import android.content.Context
import com.fuseos.app.core.Config
import com.fuseos.app.core.DeviceInfo
import com.fuseos.app.net.LanTransport
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.serialization.kotlinx.json.json
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
    lateinit var session: SessionStore
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
        val sessionStore = SessionStore(appContext)
        val deviceInfo = DeviceInfo(appContext)

        session = sessionStore
        authRepository = AuthRepository(AuthApi(httpClient, Config.BASE_URL), sessionStore)

        val controlPlaneApi = ControlPlaneApi(httpClient, Config.BASE_URL) { sessionStore.currentToken() }
        deviceRepository = DeviceRepository(controlPlaneApi, sessionStore, deviceInfo)

        val transport = LanTransport(appScope, sessionStore)
        lanTransport = transport
        signalClient = SignalClient(
            client = httpClient,
            signalUrl = Config.SIGNAL_URL,
            scope = appScope,
            batteryProvider = { deviceInfo.batteryPercent() },
            // The listener binds an ephemeral port, so this is null until it is up and
            // changes across restarts — hence a provider rather than a fixed value.
            lanAddressProvider = { transport.lanAddress() },
        )
    }
}
