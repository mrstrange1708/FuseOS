package com.fuseos.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.fuseos.app.MainActivity
import com.fuseos.app.capture.CaptureActivity
import com.fuseos.app.R
import com.fuseos.app.data.ServiceLocator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Keeps the LAN listener and the `/signal` socket alive while FuseOS is off screen.
 *
 * Without this Android freezes the process within minutes of backgrounding, the socket
 * dies, and the Mac shows the phone as offline — so a copy on the Mac has nowhere to land.
 * The service exists only to hold the process open; the stack itself lives in
 * [com.fuseos.app.data.ServiceLocator] singletons and is started through `ConnectionManager`.
 *
 * **This does not make clipboard *capture* work in the background.** Android refuses
 * clipboard reads to any app that isn't on screen, and a foreground service does not
 * change that — see `docs/protocol.md`. Sending from the background is the Share sheet's
 * job ([ShareActivity]); this service is what makes receiving work.
 */
class FuseConnectionService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var startJob: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForegroundNotification()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Signing out stops the service; a signed-out process has nothing to keep alive
        // and an ongoing notification would be a lie.
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (startJob?.isActive != true) {
            // The island is the only feedback a user gets while FuseOS is off screen, so
            // it is driven from here — the one component guaranteed to be alive whenever
            // a clip can arrive.
            scope.launch {
                ServiceLocator.clipboardSync.events.collect { entry ->
                    ServiceLocator.clipIsland.clip(entry)
                }
            }
            startJob = scope.launch {
                // Fail soft: the phone may be off-network at boot. The dashboard and the
                // Share sheet both retry through the same ConnectionManager.
                runCatching { ServiceLocator.connectionManager.ensureStarted() }
            }
        }
        // START_STICKY: if Android kills us for memory, come back — continuity is the
        // product, and an intent-less restart is exactly the "just reconnect" we want.
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun startForegroundNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Device connection",
                    // LOW: no sound, no heads-up. This notification is a permanent
                    // status line, not an event worth interrupting anyone for.
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = "Keeps FuseOS connected to your other devices." },
            )
        }

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        // The second route out of the phone, next to the Quick Settings tile. The
        // ongoing notification is already in the shade whenever we are connected, so an
        // action on it costs the user nothing and is reachable from inside any app.
        val send = PendingIntent.getActivity(
            this,
            1,
            CaptureActivity.intent(this),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FuseOS is connected")
            .setContentText("Your clipboard and files can reach this device.")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(R.drawable.ic_notification, "Send clipboard", send)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val CHANNEL_ID = "fuseos_connection"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "com.fuseos.app.STOP"

        /** Safe to call repeatedly; a running service just gets another onStartCommand. */
        fun start(context: Context) {
            val intent = Intent(context, FuseConnectionService::class.java)
            // Fail soft: background-start limits can refuse this (a peer message arriving
            // while the app is dead, say). Losing the service is a degraded connection,
            // never a crash.
            runCatching { context.startForegroundService(intent) }
        }

        fun stop(context: Context) {
            val intent = Intent(context, FuseConnectionService::class.java).setAction(ACTION_STOP)
            runCatching { context.startService(intent) }
        }
    }
}
