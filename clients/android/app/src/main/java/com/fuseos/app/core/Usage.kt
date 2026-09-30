package com.fuseos.app.core

import android.app.Application
import com.fuseos.app.BuildConfig
import com.fuseos.proto.Envelope
import com.fuseos.proto.PhoneCommand
import com.fuseos.proto.ScreenControl
import com.fuseos.proto.SidecarControl
import com.posthog.PostHog
import com.posthog.PersonProfiles
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig

/**
 * Product analytics (PostHog): which features people use, how often, and who is active each
 * day — counts, never content (CLAUDE.md principle 6). Every feature crosses
 * [com.fuseos.app.net.LanChannel.send], so that one call names it here from the message
 * type; nothing inside a message is read beyond its size. People are named by account id,
 * as the server names them, so one person counts once across phone, Mac and web.
 */
object Usage {
    data class Feature(val name: String, val properties: Map<String, Any> = emptyMap())

    /** A trackpad session is one use, not ten thousand moves: these count once per window. */
    private const val SESSION_WINDOW_MS = 10 * 60_000L
    private val continuous = setOf("trackpad", "notifications", "now_playing", "remote_control")
    private val lastCounted = HashMap<String, Long>()

    @Volatile private var started = false

    fun start(app: Application) {
        if (BuildConfig.POSTHOG_KEY.isEmpty()) return
        val config = PostHogAndroidConfig(BuildConfig.POSTHOG_KEY, BuildConfig.POSTHOG_HOST).apply {
            captureApplicationLifecycleEvents = true // "Application Opened": daily actives
            captureScreenViews = false
            captureDeepLinks = false // a link can carry anything
            sessionReplay = false
            personProfiles = PersonProfiles.IDENTIFIED_ONLY
        }
        PostHogAndroid.setup(app, config)
        PostHog.register("environment", if (BuildConfig.DEBUG) "debug" else "production")
        started = true
    }

    fun identify(userId: String) {
        if (started) PostHog.identify(userId)
    }

    /** Signed out: the next person on this phone is someone else. */
    fun reset() {
        if (started) PostHog.reset()
    }

    /** The "Usage statistics" switch. PostHog keeps the choice across launches. */
    var enabled: Boolean
        get() = started && !PostHog.isOptOut()
        set(on) {
            if (!started) return
            if (on) PostHog.optIn() else PostHog.optOut()
        }

    fun sent(envelope: Envelope) {
        if (!started) return
        val feature = featureOf(envelope) ?: return
        if (!shouldCount(feature.name, System.currentTimeMillis())) return
        PostHog.capture("feature_used", properties = mapOf("feature" to feature.name) + feature.properties)
    }

    @Synchronized
    internal fun shouldCount(name: String, nowMs: Long): Boolean {
        if (name !in continuous) return true
        val last = lastCounted[name]
        if (last != null && nowMs - last < SESSION_WINDOW_MS) return false
        lastCounted[name] = nowMs
        return true
    }

    /** The feature a message starts, or null for plumbing (acks, chunks, frames, status). */
    internal fun featureOf(envelope: Envelope): Feature? = when (envelope.bodyCase) {
        Envelope.BodyCase.CLIP_TEXT -> Feature("clipboard_text")
        Envelope.BodyCase.CLIP_IMAGE ->
            Feature("clipboard_image", mapOf("sizeBytes" to envelope.clipImage.data.size()))
        Envelope.BodyCase.FILE_META -> Feature("file_transfer", mapOf("sizeBytes" to envelope.fileMeta.size))
        Envelope.BodyCase.SCREEN_CONTROL ->
            if (envelope.screenControl.action != ScreenControl.Action.START) null
            else Feature("screen_mirroring", mapOf("remoteControl" to envelope.screenControl.remoteControl))
        Envelope.BodyCase.SIDECAR_CONTROL ->
            if (envelope.sidecarControl.action != SidecarControl.Action.START) null else Feature("sidecar")
        Envelope.BodyCase.PHONE_COMMAND ->
            if (envelope.phoneCommand.action != PhoneCommand.Action.RING) null else Feature("ring_phone")
        Envelope.BodyCase.OPEN_LINK -> Feature("open_link")
        Envelope.BodyCase.MEDIA_COMMAND -> Feature("now_playing")
        Envelope.BodyCase.POINTER_INPUT -> Feature("trackpad")
        Envelope.BodyCase.REMOTE_INPUT -> Feature("remote_control")
        Envelope.BodyCase.PHONE_NOTIFICATION -> Feature("notifications")
        Envelope.BodyCase.NOTIFICATION_REPLY -> Feature("notification_reply")
        Envelope.BodyCase.NOTIFICATION_OPEN -> Feature("notification_open")
        Envelope.BodyCase.CALL_ACTION ->
            Feature("call", mapOf("action" to envelope.callAction.action.name.lowercase()))
        Envelope.BodyCase.UNLOCKED -> Feature("unlock")
        else -> null
    }
}
