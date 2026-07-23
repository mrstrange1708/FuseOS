package com.fuseos.app.core

object Config {
    /**
     * Base URL of the FuseOS control-plane server (`pnpm --filter server dev`, port 3000).
     *
     * - Physical phone (current): your Mac's LAN IP — phone must be on the SAME Wi-Fi.
     * - Android emulator instead: use "http://10.0.2.2:3000" (the emulator's alias
     *   for the host's localhost).
     *
     * Your Mac's Wi-Fi IP can change when it rejoins a network; update it here if
     * the app can't reach the server.
     */
    const val BASE_URL: String = "http://192.168.0.112:3000"

    /** The `/signal` presence WebSocket on the same server (http → ws). */
    val SIGNAL_URL: String = BASE_URL.replaceFirst("http", "ws") + "/signal"
}
