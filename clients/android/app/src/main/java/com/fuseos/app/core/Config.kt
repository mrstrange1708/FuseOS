package com.fuseos.app.core

import com.fuseos.app.BuildConfig

object Config {
    /**
     * Base URL of the FuseOS control-plane server (`pnpm --filter server dev`, port 3000).
     *
     * Baked in at build time from the `serverUrl` Gradle property — `./dev.sh` passes
     * this Mac's current LAN IP, so a Wi-Fi address change needs no code edit. Override
     * by hand with `./gradlew installDebug -PserverUrl=http://10.0.2.2:3000` (the
     * emulator's alias for the host's localhost).
     */
    const val BASE_URL: String = BuildConfig.SERVER_URL

    /** The `/signal` presence WebSocket on the same server (http → ws). */
    val SIGNAL_URL: String = BASE_URL.replaceFirst("http", "ws") + "/signal"
}
