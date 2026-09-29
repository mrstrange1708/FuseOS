package com.fuseos.app.actions

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import com.fuseos.app.R
import com.fuseos.app.core.BackgroundLaunch
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.Envelope
import com.fuseos.proto.OpenLink
import com.fuseos.proto.Outcome
import com.fuseos.proto.PhoneCommand
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * What the Mac can ask this phone to do (`PhoneCommand`, `OpenLink` in the proto): ring it,
 * open a link — and the phone's side of Handoff, sending a link the other
 * way.
 */
class PhoneActions(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val app = context.applicationContext
    private var ringtone: Ringtone? = null
    private var ringTimeout: Job? = null
    private var restoreVolume: Int? = null

    init {
        scope.launch {
            transport.incoming.collect { envelope ->
                when (envelope.bodyCase) {
                    Envelope.BodyCase.PHONE_COMMAND -> when (envelope.phoneCommand.action) {
                        PhoneCommand.Action.RING -> ring()
                        PhoneCommand.Action.STOP_RING -> stopRing()
                        else -> Unit
                    }
                    Envelope.BodyCase.OPEN_LINK -> openLink(envelope.openLink.url)
                    Envelope.BodyCase.OUTCOME -> showOutcome(envelope.outcome)
                    else -> Unit
                }
            }
        }
    }

    /**
     * "Open copied link" on the phone: the first web link on this phone's clipboard opens
     * in the Mac's browser. `clipText` is read by the caller, which has focus (Android lets
     * only the focused app read the clipboard). Every outcome is said in the island.
     */
    fun openCopiedLinkOnMac(clipText: String?) {
        val island = com.fuseos.app.data.ServiceLocator.clipIsland
        val url = clipText?.let(::firstLink)
            ?: return island.error("No link on your clipboard", "Copy a web link first, then tap Open on Mac.")
        if (transport.connectedPeers.value.isEmpty()) {
            return island.error("Mac isn't linked", "Open FuseOS on your Mac, on the same Wi-Fi.")
        }
        sendLink(url)
        island.status("Opening on your Mac", android.net.Uri.parse(url).host ?: url)
    }

    /** The Mac's word on something this phone asked of it — an unlock, a link. */
    private fun showOutcome(outcome: Outcome) {
        val island = com.fuseos.app.data.ServiceLocator.clipIsland
        val title = when (outcome.kind) {
            Outcome.Kind.UNLOCK -> if (outcome.ok) "Mac unlocked" else "Mac didn't unlock"
            Outcome.Kind.OPEN_LINK -> if (outcome.ok) "Opened on your Mac" else "Link not opened"
            else -> if (outcome.ok) "Done" else "That didn't work"
        }
        if (outcome.ok) {
            island.status(title, outcome.detail.ifEmpty { "On your Mac" })
        } else {
            island.error(title, outcome.detail.ifEmpty { "Your Mac couldn't do it." })
        }
    }

    /** Handoff, phone → Mac. Returns false for anything that is not an http(s) link. */
    fun sendLink(url: String): Boolean {
        if (!isWebLink(url) || transport.connectedPeers.value.isEmpty()) return false
        scope.launch(Dispatchers.IO) {
            transport.broadcast(transport.newEnvelope().setOpenLink(OpenLink.newBuilder().setUrl(url)).build())
        }
        return true
    }

    private fun openLink(url: String) {
        if (!isWebLink(url)) return
        BackgroundLaunch.start(
            app,
            Intent(Intent.ACTION_VIEW, Uri.parse(url)),
            title = "Link from your Mac",
            text = url,
            notificationId = LINK_ID,
        )
    }

    /** Loud, on the alarm stream so silent mode does not mute it, for at most 30 s. */
    private fun ring() {
        stopRing()
        val audio = app.getSystemService(AudioManager::class.java)
        restoreVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        ringtone = RingtoneManager.getRingtone(app, uri)?.apply {
            audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
            play()
        }
        showRingingNotification()
        ringTimeout = scope.launch {
            delay(RING_MS)
            stopRing()
        }
    }

    fun stopRing() {
        ringTimeout?.cancel()
        ringTimeout = null
        ringtone?.stop()
        ringtone = null
        restoreVolume?.let {
            app.getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM, it, 0)
        }
        restoreVolume = null
        app.getSystemService(NotificationManager::class.java).cancel(RING_ID)
    }

    private fun showRingingNotification() {
        val manager = app.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(RING_CHANNEL, "Find my phone", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        val stop = PendingIntent.getBroadcast(
            app, RING_ID, Intent(app, StopRingReceiver::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            RING_ID,
            NotificationCompat.Builder(app, RING_CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Your Mac is ringing this phone")
                .setContentText("Tap to stop")
                .setContentIntent(stop)
                .addAction(0, "Stop", stop)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .build(),
        )
    }

    companion object {
        private const val RING_CHANNEL = "fuseos_ring"
        private const val RING_ID = 51
        private const val LINK_ID = 53
        private const val RING_MS = 30_000L

        fun isWebLink(url: String): Boolean =
            url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true)

        /** The first http(s) link in some shared text, or null. */
        fun firstLink(text: String): String? =
            Regex("""https?://\S+""", RegexOption.IGNORE_CASE).find(text)?.value?.trimEnd('.', ',', ')', ']')
    }
}

/** The ringing notification's Stop. */
class StopRingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        com.fuseos.app.data.ServiceLocator.phoneActions.stopRing()
    }
}
