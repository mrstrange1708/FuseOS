package com.fuseos.app.notify

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.fuseos.app.net.LanTransport
import com.fuseos.proto.Envelope
import com.fuseos.proto.MediaCommand
import com.fuseos.proto.MediaState
import com.google.protobuf.ByteString
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Now Playing, phone → Mac, and the Mac's play/pause/skip back.
 *
 * Other apps' media sessions are readable only by an enabled notification listener, which
 * FuseOS already is for notification sync — so this starts when that listener connects and
 * stops when it goes. The session followed is the one playing, else the most recent.
 */
class MediaSync(
    context: Context,
    private val transport: LanTransport,
    private val scope: CoroutineScope,
) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val manager = app.getSystemService(MediaSessionManager::class.java)
    private val listenerComponent = ComponentName(app, FuseNotificationListener::class.java)
    private var controller: MediaController? = null
    /** The last state sent, minus position, so a seek-only tick does not resend artwork. */
    private var lastSent: MediaState? = null

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = publish()
        override fun onPlaybackStateChanged(state: PlaybackState?) = publish()
        override fun onSessionDestroyed() = follow(null)
    }

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { sessions ->
        follow(pick(sessions.orEmpty()))
    }

    init {
        scope.launch {
            transport.incoming.collect { envelope ->
                if (envelope.bodyCase == Envelope.BodyCase.MEDIA_COMMAND) main.post { command(envelope.mediaCommand) }
            }
        }
        // A Mac that just connected gets the current track straight away.
        scope.launch {
            var previous = emptySet<String>()
            transport.connectedPeers.collect { now ->
                if ((now - previous).isNotEmpty()) {
                    lastSent = null
                    main.post { publish() }
                }
                previous = now
            }
        }
    }

    /** Called when notification access is live — the only time sessions are readable. */
    fun start() = main.post {
        runCatching {
            manager.addOnActiveSessionsChangedListener(sessionsChanged, listenerComponent, main)
            follow(pick(manager.getActiveSessions(listenerComponent)))
        }
    }

    fun stop() = main.post {
        runCatching { manager.removeOnActiveSessionsChangedListener(sessionsChanged) }
        follow(null)
    }

    private fun pick(sessions: List<MediaController>): MediaController? =
        sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: sessions.firstOrNull()

    private fun follow(next: MediaController?) {
        if (next?.sessionToken == controller?.sessionToken) return
        controller?.unregisterCallback(callback)
        controller = next
        next?.registerCallback(callback, main)
        publish()
    }

    private fun command(command: MediaCommand) {
        val controls = controller?.transportControls ?: return
        when (command.action) {
            MediaCommand.Action.PLAY_PAUSE ->
                if (controller?.playbackState?.state == PlaybackState.STATE_PLAYING) controls.pause() else controls.play()
            MediaCommand.Action.NEXT -> controls.skipToNext()
            MediaCommand.Action.PREVIOUS -> controls.skipToPrevious()
            MediaCommand.Action.SEEK -> controls.seekTo(command.positionMs)
            else -> Unit
        }
    }

    private fun publish() {
        if (transport.connectedPeers.value.isEmpty()) return
        val state = snapshot()
        val comparable = state.toBuilder().clearPositionMs().clearPositionAtUnixMs().clearArtworkJpeg().build()
        val unchanged = lastSent?.let { it == comparable } == true
        // Position alone changing is not news: the Mac advances the bar itself while playing.
        if (unchanged && state.playing) return
        val sameTrack = lastSent?.title == state.title && lastSent?.artist == state.artist
        lastSent = comparable
        val outgoing = if (sameTrack) state.toBuilder().clearArtworkJpeg().build() else state
        scope.launch(Dispatchers.IO) {
            transport.broadcast(transport.newEnvelope().setMediaState(outgoing).build())
        }
    }

    private fun snapshot(): MediaState {
        val controller = controller ?: return MediaState.newBuilder().setActive(false).build()
        val metadata = controller.metadata
        val playback = controller.playbackState
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
        if (metadata == null || title.isBlank()) return MediaState.newBuilder().setActive(false).build()
        // PlaybackState.position was true at lastPositionUpdateTime; carry it to "now".
        val now = System.currentTimeMillis()
        val position = playback?.let {
            val drift = if (it.state == PlaybackState.STATE_PLAYING) {
                ((SystemClock.elapsedRealtime() - it.lastPositionUpdateTime) * it.playbackSpeed).toLong()
            } else {
                0L
            }
            it.position + drift
        } ?: 0L
        return MediaState.newBuilder()
            .setActive(true)
            .setAppName(appName(controller.packageName))
            .setTitle(title)
            .setArtist(metadata.getString(MediaMetadata.METADATA_KEY_ARTIST).orEmpty())
            .setAlbum(metadata.getString(MediaMetadata.METADATA_KEY_ALBUM).orEmpty())
            .setPlaying(playback?.state == PlaybackState.STATE_PLAYING)
            .setPositionMs(position.coerceAtLeast(0))
            .setPositionAtUnixMs(now)
            .setDurationMs(metadata.getLong(MediaMetadata.METADATA_KEY_DURATION).coerceAtLeast(0))
            .setArtworkJpeg(artwork(metadata))
            .build()
    }

    private fun artwork(metadata: MediaMetadata): ByteString {
        val bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
            ?: return ByteString.EMPTY
        return runCatching {
            val side = ARTWORK_PX.toFloat() / maxOf(bitmap.width, bitmap.height)
            val scaled = if (side < 1f) {
                Bitmap.createScaledBitmap(bitmap, (bitmap.width * side).toInt(), (bitmap.height * side).toInt(), true)
            } else {
                bitmap
            }
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
            ByteString.copyFrom(out.toByteArray())
        }.getOrDefault(ByteString.EMPTY)
    }

    private fun appName(pkg: String): String = runCatching {
        val pm = app.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    }.getOrDefault(pkg)

    private companion object {
        const val ARTWORK_PX = 256
    }
}
