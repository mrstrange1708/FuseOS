package com.fuseos.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.fuseos.app.data.ServiceLocator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Brings the connection back after the phone reboots, without anyone opening the app.
 *
 * Until this existed, a restart left FuseOS dead until the user launched it by hand — so
 * the first copy on the Mac after a reboot had nowhere to land, which is exactly when a
 * continuity app has to be there. `BOOT_COMPLETED` is one of the documented exemptions
 * from the background foreground-service start restrictions, so this is allowed to start
 * the service directly.
 *
 * Only for a signed-in install: a signed-out process has nothing to connect and an
 * ongoing notification would be a lie.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val appContext = context.applicationContext
        // goAsync() rather than a bare launch: a receiver's process can be killed the
        // moment onReceive returns, and reading the token is a DataStore round trip.
        val pending = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // FuseApp.onCreate has already run ServiceLocator.init by the time a
                // receiver fires — the process is built before the broadcast is delivered.
                if (ServiceLocator.session.currentToken() != null) {
                    FuseConnectionService.start(appContext)
                }
            } finally {
                pending.finish()
            }
        }
    }
}
