package com.fuseos.app.trust

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.fuseos.app.MainActivity
import com.fuseos.app.R
import com.fuseos.app.data.PeerPresence
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.net.LanTransport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Asks about each device on the account this phone hasn't approved — new, or back with a
 * different key — with a notification (Allow / Not mine, answerable without opening the app)
 * and, while the app is open, a dialog. Nothing reaches the device until Allow.
 */
class TrustPrompts(
    private val app: Context,
    private val trust: DeviceTrust,
    private val transport: LanTransport,
    private val presence: StateFlow<Map<String, PeerPresence>>,
    scope: CoroutineScope,
) {
    data class Pending(val deviceId: String, val key: String, val name: String)

    private val _pending = MutableStateFlow<List<Pending>>(emptyList())
    val pending: StateFlow<List<Pending>> = _pending.asStateFlow()
    private val notified = mutableSetOf<String>()

    init {
        scope.launch { presence.collect { refresh() } }
    }

    @Synchronized
    fun refresh() {
        if (!trust.bootstrapped) return
        val list = presence.value.mapNotNull { (id, peer) ->
            val key = peer.publicKey ?: return@mapNotNull null
            if (trust.check(id, key) != DeviceTrust.Verdict.Pending) return@mapNotNull null
            Pending(id, key, peer.name ?: "A new device")
        }
        _pending.value = list
        list.filter { notified.add("${it.deviceId}|${it.key}") }.forEach(::notify)
    }

    fun decide(deviceId: String, key: String, allow: Boolean) {
        if (allow) trust.approve(deviceId, key) else trust.block(deviceId, key)
        app.getSystemService(NotificationManager::class.java).cancel(deviceId.hashCode())
        refresh()
        if (allow) transport.retryNow()
    }

    /** Signed out: a different account's devices, asked about afresh. */
    fun forget() {
        trust.reset()
        synchronized(this) { notified.clear() }
        _pending.value = emptyList()
    }

    private fun notify(p: Pending) {
        val manager = app.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "New devices", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        fun action(allow: Boolean) = PendingIntent.getBroadcast(
            app,
            p.deviceId.hashCode() * 2 + if (allow) 1 else 0,
            Intent(app, TrustActionReceiver::class.java)
                .putExtra(EXTRA_ID, p.deviceId).putExtra(EXTRA_KEY, p.key).putExtra(EXTRA_ALLOW, allow),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val open = PendingIntent.getActivity(
            app, 0, Intent(app, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            p.deviceId.hashCode(),
            NotificationCompat.Builder(app, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Allow “${p.name}” to link with this phone?")
                .setStyle(NotificationCompat.BigTextStyle().bigText(BODY))
                .setContentText(BODY)
                .setContentIntent(open)
                .addAction(0, "Allow", action(true))
                .addAction(0, "Not mine", action(false))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build(),
        )
    }

    companion object {
        const val BODY = "It just signed in to your FuseOS account. Allow it only if it's yours: " +
            "it will get what you copy, your files, and this phone's notifications and codes."
        private const val CHANNEL = "fuseos_new_devices"
        const val EXTRA_ID = "device_id"
        const val EXTRA_KEY = "device_key"
        const val EXTRA_ALLOW = "allow"
    }
}

/** The notification's Allow / Not mine. Not exported: only our own PendingIntents reach it. */
class TrustActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(TrustPrompts.EXTRA_ID) ?: return
        val key = intent.getStringExtra(TrustPrompts.EXTRA_KEY) ?: return
        ServiceLocator.trustPrompts.decide(id, key, intent.getBooleanExtra(TrustPrompts.EXTRA_ALLOW, false))
    }
}
