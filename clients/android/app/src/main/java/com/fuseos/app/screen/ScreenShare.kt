package com.fuseos.app.screen

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.fuseos.app.R
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.Envelope
import com.fuseos.proto.ScreenControl
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * The phone end of screen mirroring's control channel: the Mac asks, the user consents
 * here, [ScreenShareService] streams. Mirroring also ends if the Mac drops off the LAN —
 * encoding a screen for nobody is battery spent on nothing.
 */
class ScreenShare(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext

    init {
        scope.launch {
            transport.incoming.collect { envelope ->
                if (envelope.bodyCase != Envelope.BodyCase.SCREEN_CONTROL) return@collect
                when (envelope.screenControl.action) {
                    ScreenControl.Action.START -> askForConsent()
                    ScreenControl.Action.STOP -> ScreenShareService.stop(appContext)
                    ScreenControl.Action.KEYFRAME -> ScreenShareService.requestKeyframe()
                    else -> Unit
                }
            }
        }
        scope.launch {
            transport.connectedPeers.collect { if (it.isEmpty()) ScreenShareService.stop(appContext) }
        }
    }

    /** Safe from any thread: the socket write happens on IO. */
    fun send(action: ScreenControl.Action) {
        scope.launch(Dispatchers.IO) {
            transport.broadcast(
                transport.newEnvelope().setScreenControl(ScreenControl.newBuilder().setAction(action)).build(),
            )
        }
    }

    /**
     * Android's own consent dialog has to come from an activity. Holding the overlay
     * permission (the island's) exempts an app from the background-activity-launch block,
     * so with it the dialog opens straight away; without it a notification is the way in.
     */
    private fun askForConsent() {
        val intent = Intent(appContext, ScreenConsentActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Settings.canDrawOverlays(appContext) && runCatching { appContext.startActivity(intent) }.isSuccess) {
            return
        }
        val manager = appContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(REQUEST_CHANNEL, "Screen sharing requests", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        val tap = PendingIntent.getActivity(
            appContext, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.notify(
            REQUEST_ID,
            NotificationCompat.Builder(appContext, REQUEST_CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Your Mac wants to see your screen")
                .setContentText("Tap to choose whether to share it")
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build(),
        )
    }

    private companion object {
        const val REQUEST_CHANNEL = "fuseos_screen_request"
        const val REQUEST_ID = 42
    }
}
