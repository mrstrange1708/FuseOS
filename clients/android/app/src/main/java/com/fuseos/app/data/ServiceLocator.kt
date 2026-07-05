package com.fuseos.app.data

import android.content.Context
import com.fuseos.app.core.Config
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

/** Minimal manual dependency container, initialised once from [FuseApp]. */
object ServiceLocator {

    lateinit var authRepository: AuthRepository
        private set

    fun init(context: Context) {
        val httpClient = HttpClient(OkHttp) {
            expectSuccess = false
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
        val api = AuthApi(httpClient, Config.BASE_URL)
        val session = SessionStore(context.applicationContext)
        authRepository = AuthRepository(api, session)
    }
}
