package com.fuseos.app.notify

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.CallState
import com.fuseos.proto.Envelope
import com.fuseos.proto.NotificationDismiss
import com.fuseos.proto.Outcome
import com.fuseos.proto.PhoneNotification
import com.google.protobuf.ByteString
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The phone end of notification sync (`PhoneNotification` in the proto).
 *
 * The phone is the only origin. What it posts goes to the Mac while one is linked and is
 * dropped otherwise — an hour-old notification is not worth delivering late. A dismissal
 * that came *from* the Mac is remembered so the removal it causes here is not echoed back.
 *
 * Notification text is user content: it goes over the encrypted LAN channel and nowhere
 * else — never a log line, never analytics.
 */
class NotificationSync(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("notification-sync", Context.MODE_PRIVATE)
    private val icons = ConcurrentHashMap<String, ByteString>()
    /** Keys the Mac cleared, so their removal here is not reported back to it. */
    private val clearedByPeer = ConcurrentHashMap.newKeySet<String>()

    private val _enabled = MutableStateFlow(prefs.getBoolean(KEY_ENABLED, true))
    /** The user's switch. Access itself is granted in system settings, see [hasAccess]. */
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun setEnabled(on: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, on).apply()
        _enabled.value = on
    }

    /** Whether the user has granted FuseOS notification access in system settings. */
    fun hasAccess(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(appContext).contains(appContext.packageName)

    /** Where the user grants access. */
    fun accessSettingsIntent() = android.content.Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Each replyable notification's inline-reply action, by key, for the Mac's replies. */
    private val replyActions = object : LinkedHashMap<String, Notification.Action>() {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Notification.Action>) = size > 200
    }
    /** Each forwarded notification's tap action, by key, for "open it" from the Mac. */
    private val contentIntents = object : LinkedHashMap<String, android.app.PendingIntent>() {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, android.app.PendingIntent>) = size > 200
    }
    /** Forwarded notifications that have no tap action at all — "gone" would be a lie. */
    private val withoutTapAction = ConcurrentHashMap.newKeySet<String>()
    private val liveSentAt = ConcurrentHashMap<String, Long>()

    /** The call notification being mirrored, and its actions (the fallback for answering). */
    @Volatile private var call: StatusBarNotification? = null
    /** Declared before `init`: its collector may run before later properties exist. */
    val calls = CallControl(appContext)

    init {
        scope.launch {
            transport.incoming.collect { envelope ->
                when (envelope.bodyCase) {
                    // The Mac clearing one of ours: clear it here too.
                    Envelope.BodyCase.NOTIFICATION_DISMISS -> {
                        val key = envelope.notificationDismiss.key
                        clearedByPeer += key
                        FuseNotificationListener.instance?.runCatching { cancelNotification(key) }
                    }
                    Envelope.BodyCase.NOTIFICATION_REPLY ->
                        reply(envelope.notificationReply.key, envelope.notificationReply.text)
                    Envelope.BodyCase.NOTIFICATION_OPEN -> open(envelope.notificationOpen.key)
                    Envelope.BodyCase.CALL_ACTION -> calls.perform(envelope.callAction.action, call)
                    else -> Unit
                }
            }
        }
    }

    /**
     * Fills the app's own inline-reply action, as if the user had typed in the shade. This
     * is how an SMS or chat reply goes out with no SMS permission at all.
     */
    private fun reply(key: String, text: String) {
        if (text.isBlank()) return
        val action = synchronized(replyActions) { replyActions[key] }
        val inputs = action?.remoteInputs
        if (action == null || inputs == null) {
            return outcome(Outcome.Kind.REPLY, false, "That notification is gone from the phone, so there's nothing to reply to.")
        }
        val sent = runCatching {
            val results = android.os.Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
            val intent = android.content.Intent()
            android.app.RemoteInput.addResultsToIntent(inputs, intent, results)
            action.actionIntent.send(appContext, 0, intent)
        }.isSuccess
        outcome(Outcome.Kind.REPLY, sent, if (sent) "" else "The app on the phone refused the reply.")
    }

    /**
     * Opens a notification as a tap in the shade would: its app's own content intent. A
     * background start needs FuseOS's overlay permission (the exemption Android grants it),
     * so without it this says so rather than firing an intent Android will quietly drop.
     */
    private fun open(key: String) {
        val intent = synchronized(contentIntents) { contentIntents[key] }
            ?: return outcome(
                Outcome.Kind.OPEN_NOTIFICATION, false,
                if (key in withoutTapAction) "It doesn't open anything on the phone. Its app gave it no tap action."
                else "That notification is gone from the phone.",
            )
        if (!Settings.canDrawOverlays(appContext)) {
            return outcome(
                Outcome.Kind.OPEN_NOTIFICATION, false,
                "On the phone, allow FuseOS to display over other apps so it can open things for your Mac.",
            )
        }
        val options = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            android.app.ActivityOptions.makeBasic()
                .setPendingIntentBackgroundActivityStartMode(android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                .toBundle()
        } else {
            null
        }
        val opened = runCatching { intent.send(appContext, 0, null, null, null, null, options) }.isSuccess
        val locked = appContext.getSystemService(android.app.KeyguardManager::class.java)?.isKeyguardLocked == true
        outcome(
            Outcome.Kind.OPEN_NOTIFICATION,
            opened,
            when {
                !opened -> "The app didn't open. It may have closed that notification."
                locked -> "Unlock your phone to see it."
                else -> ""
            },
        )
    }

    private fun outcome(kind: Outcome.Kind, ok: Boolean, detail: String) {
        if (transport.connectedPeers.value.isEmpty()) return
        scope.launch(Dispatchers.IO) {
            transport.broadcast(
                transport.newEnvelope()
                    .setOutcome(Outcome.newBuilder().setKind(kind).setOk(ok).setDetail(detail))
                    .build(),
            )
        }
    }

    /** A call notification (the dialer's): mirrored as a call, never as a notification. */
    private fun postedCall(sbn: StatusBarNotification, caller: String) {
        call = sbn
        val active = sbn.notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER)
        sendCall(if (active) CallState.State.ACTIVE else CallState.State.RINGING, sbn.key, caller)
    }

    private fun sendCall(state: CallState.State, key: String, caller: String) {
        if (transport.connectedPeers.value.isEmpty()) return
        scope.launch(Dispatchers.IO) {
            transport.broadcast(
                transport.newEnvelope()
                    .setCallState(CallState.newBuilder().setState(state).setKey(key).setCaller(caller))
                    .build(),
            )
        }
    }

    fun posted(sbn: StatusBarNotification) {
        val n = sbn.notification
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        val progressMax = extras.getInt(Notification.EXTRA_PROGRESS_MAX)
        val indeterminate = extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE)
        val live = sbn.isOngoing && isLiveActivity(
            category = n.category,
            hasProgress = progressMax > 0 || indeterminate,
            showsClock = extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER),
            isMedia = extras.containsKey(Notification.EXTRA_MEDIA_SESSION),
        )
        val forward = shouldForward(
            enabled = _enabled.value,
            linked = transport.connectedPeers.value.isNotEmpty(),
            fromSelf = sbn.packageName == appContext.packageName,
            ongoing = sbn.isOngoing,
            groupSummary = n.flags and Notification.FLAG_GROUP_SUMMARY != 0,
            hasContent = title.isNotBlank() || text.isNotBlank(),
            liveActivity = live,
        )
        if (n.category == Notification.CATEGORY_CALL && sbn.packageName != appContext.packageName) {
            if (_enabled.value) postedCall(sbn, title)
            return
        }
        if (!forward) return
        // A download ticks its progress many times a second; the Mac needs about one a second.
        if (live) {
            val now = android.os.SystemClock.elapsedRealtime()
            val last = liveSentAt[sbn.key] ?: 0L
            if (now - last < LIVE_MIN_INTERVAL_MS) return
            liveSentAt[sbn.key] = now
        }
        val replyAction = n.actions?.firstOrNull { it.remoteInputs?.isNotEmpty() == true }
        if (replyAction != null) synchronized(replyActions) { replyActions[sbn.key] = replyAction }
        if (n.contentIntent != null) {
            synchronized(contentIntents) { contentIntents[sbn.key] = n.contentIntent }
            withoutTapAction.remove(sbn.key)
        } else {
            withoutTapAction.add(sbn.key)
        }
        scope.launch(Dispatchers.IO) {
            val message = PhoneNotification.newBuilder()
                .setKey(sbn.key)
                .setPackage(sbn.packageName)
                .setAppName(appName(sbn.packageName))
                .setTitle(title)
                .setText(text.take(MAX_TEXT))
                .setIconPng(icon(sbn.packageName))
                .setPostedAtUnixMs(sbn.postTime)
                .setCanReply(replyAction != null)
                .setOngoing(live)
                .setProgress(extras.getInt(Notification.EXTRA_PROGRESS))
                .setProgressMax(progressMax)
                .setIndeterminate(indeterminate)
            transport.broadcast(transport.newEnvelope().setPhoneNotification(message).build())
        }
    }

    fun removed(sbn: StatusBarNotification) {
        if (call?.key == sbn.key) {
            call = null
            sendCall(CallState.State.ENDED, sbn.key, "")
            return
        }
        synchronized(replyActions) { replyActions.remove(sbn.key) }
        synchronized(contentIntents) { contentIntents.remove(sbn.key) }
        withoutTapAction.remove(sbn.key)
        liveSentAt.remove(sbn.key)
        if (clearedByPeer.remove(sbn.key)) return
        if (!_enabled.value || transport.connectedPeers.value.isEmpty()) return
        scope.launch(Dispatchers.IO) {
            transport.broadcast(
                transport.newEnvelope()
                    .setNotificationDismiss(NotificationDismiss.newBuilder().setKey(sbn.key))
                    .build(),
            )
        }
    }

    private fun appName(pkg: String): String = runCatching {
        val pm = appContext.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    }.getOrDefault(pkg)

    /** The app's icon as a small PNG, cached per package: icons do not change per post. */
    private fun icon(pkg: String): ByteString = icons.getOrPut(pkg) {
        runCatching {
            val drawable = appContext.packageManager.getApplicationIcon(pkg)
            val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, ICON_PX, ICON_PX)
            drawable.draw(Canvas(bitmap))
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            ByteString.copyFrom(out.toByteArray())
        }.getOrDefault(ByteString.EMPTY)
    }

    companion object {
        private const val KEY_ENABLED = "enabled"
        private const val ICON_PX = 64
        /** A long chat is still one notification; the Mac shows a few lines of it. */
        private const val MAX_TEXT = 1_000
        private const val LIVE_MIN_INTERVAL_MS = 1_000L

        /** Categories whose ongoing notifications are activities worth watching. */
        private val LIVE_CATEGORIES = setOf(
            Notification.CATEGORY_NAVIGATION,
            Notification.CATEGORY_PROGRESS,
            Notification.CATEGORY_STOPWATCH,
            Notification.CATEGORY_WORKOUT,
            Notification.CATEGORY_ALARM,
        )

        /**
         * Whether an ongoing notification is a live activity (a timer, a route, a delivery,
         * a download) rather than a background service's placard: it shows progress or a
         * running clock, or its category says so. Media is Now Playing's, not this.
         */
        fun isLiveActivity(category: String?, hasProgress: Boolean, showsClock: Boolean, isMedia: Boolean): Boolean =
            !isMedia && (hasProgress || showsClock || category in LIVE_CATEGORIES)

        /**
         * Which notifications cross to the Mac. Pure, so the rules are pinned by a test.
         * Not: our own (the service's ongoing one would mirror forever), ongoing ones that
         * are not live activities (a service's placard is status, not news), group
         * summaries (their children already went), or ones with nothing to read.
         */
        fun shouldForward(
            enabled: Boolean,
            linked: Boolean,
            fromSelf: Boolean,
            ongoing: Boolean,
            groupSummary: Boolean,
            hasContent: Boolean,
            liveActivity: Boolean = false,
        ): Boolean = enabled && linked && !fromSelf && (!ongoing || liveActivity) && !groupSummary && hasContent
    }
}

/**
 * The system's hook into posted notifications. Enabled by the user under Settings →
 * Notification access; everything it hears goes straight to [NotificationSync].
 */
class FuseNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        instance = this
        // Media sessions are readable only through an enabled listener: start with it.
        com.fuseos.app.data.ServiceLocator.mediaSync.start()
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
        com.fuseos.app.data.ServiceLocator.mediaSync.stop()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        com.fuseos.app.data.ServiceLocator.notificationSync.posted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        com.fuseos.app.data.ServiceLocator.notificationSync.removed(sbn)
    }

    companion object {
        /** The live listener, for clearing a notification the Mac dismissed. */
        @Volatile
        var instance: FuseNotificationListener? = null
            private set
    }
}
