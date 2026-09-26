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
import com.fuseos.app.core.BackgroundLaunch
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
                if (envelope.bodyCase != Envelope.BodyCase.SCREEN_CONTROL &&
                    envelope.bodyCase != Envelope.BodyCase.REMOTE_INPUT
                ) {
                    return@collect
                }
                if (envelope.bodyCase == Envelope.BodyCase.REMOTE_INPUT) {
                    // Only while this phone is showing its screen: the user consented to
                    // the Mac seeing it, and control never outlives that consent.
                    if (ScreenShareService.sharing.value) {
                        RemoteControlService.instance?.perform(envelope.remoteInput)
                    }
                    return@collect
                }
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
            val control = ScreenControl.newBuilder()
                .setAction(action)
                // Tells the Mac whether a click on the mirror will do anything.
                .setRemoteControl(RemoteControlService.instance != null)
            transport.broadcast(transport.newEnvelope().setScreenControl(control).build())
        }
    }

    /** Where the user turns remote control on: Settings → Accessibility. */
    fun remoteControlSettingsIntent() =
        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Android's own consent dialog has to come from an activity. Holding the overlay
     * permission (the island's) exempts an app from the background-activity-launch block,
     * so with it the dialog opens straight away; without it a notification is the way in.
     */
    private fun askForConsent() = BackgroundLaunch.start(
        appContext,
        Intent(appContext, ScreenConsentActivity::class.java),
        title = "Your Mac wants to see your screen",
        text = "Tap to choose whether to share it",
        notificationId = REQUEST_ID,
    )

    private companion object {
        const val REQUEST_ID = 42
    }
}
