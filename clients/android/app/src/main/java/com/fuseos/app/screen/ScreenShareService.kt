package com.fuseos.app.screen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Surface
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.IntentCompat
import com.fuseos.app.R
import com.fuseos.app.data.ServiceLocator
import com.fuseos.proto.ScreenControl
import com.fuseos.proto.ScreenFrame
import com.google.protobuf.ByteString
import kotlin.concurrent.thread

/**
 * Streams the screen to the Mac: MediaProjection → a virtual display drawing straight into
 * a hardware H.264 encoder's input surface → each encoded access unit as a `ScreenFrame`
 * on the existing encrypted LAN channel. No pixel ever passes through app memory.
 *
 * Tuned for latency, not quality: realtime priority, 30 fps, a keyframe every 2 s, the
 * codec config prepended to every keyframe so the Mac can join or recover at any one, and
 * the last frame repeated while the screen is still so a static screen is never stale.
 * A rotation swaps in an encoder at the new size (see [onConfigurationChanged]).
 */
class ScreenShareService : Service() {
    private var projection: MediaProjection? = null
    private var codec: MediaCodec? = null
    private var display: VirtualDisplay? = null
    private var pump: Thread? = null
    /** A sharing session is running (from consent until [finish]). */
    @Volatile private var active = false
    /** The current encoder's drain loop should keep going; cleared to swap encoders. */
    @Volatile private var pumping = false
    private var encoding: CaptureSize? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            finish(notifyMac = true)
            return START_NOT_STICKY
        }
        val data = intent?.let { IntentCompat.getParcelableExtra(it, EXTRA_DATA, Intent::class.java) }
        if (data == null || active) return START_NOT_STICKY
        // Must be foreground, with the mediaProjection type, before the projection exists.
        startInForeground()
        val mpm = getSystemService(MediaProjectionManager::class.java)
        val projection = runCatching { mpm.getMediaProjection(intent.getIntExtra(EXTRA_CODE, 0), data) }.getOrNull()
        if (projection == null) {
            finish(notifyMac = true)
            return START_NOT_STICKY
        }
        this.projection = projection
        // Required before capturing (API 34), and how "Stop sharing" from the system
        // status chip reaches us.
        projection.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() = finish(notifyMac = true)
            },
            Handler(Looper.getMainLooper()),
        )
        runCatching { begin(projection) }.onFailure { finish(notifyMac = true) }
        return START_NOT_STICKY
    }

    private fun begin(projection: MediaProjection) {
        val size = captureSize()
        val surface = startEncoder(size)
        display = projection.createVirtualDisplay(
            "FuseOS", size.width, size.height, size.dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null,
        )
        active = true
        running = this
        ServiceLocator.screenShare.send(ScreenControl.Action.START)
    }

    /**
     * A rotation: the same display, resized, drawing into a new encoder at the new size.
     * Android 14 allows one virtual display per projection, so the display is resized
     * rather than recreated. The new encoder's first frame carries the new SPS, which is
     * how the Mac learns the new shape.
     */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val display = display ?: return
        val size = captureSize()
        if (!active || size == encoding) return
        stopEncoder()
        val surface = runCatching { startEncoder(size) }.getOrElse {
            finish(notifyMac = true)
            return
        }
        display.resize(size.width, size.height, size.dpi)
        display.surface = surface
    }

    /** A fresh encoder at [size], with its drain thread running. Returns its input surface. */
    private fun startEncoder(size: CaptureSize): Surface {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, size.width, size.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, KEYFRAME_SECONDS)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000)
            setInteger(MediaFormat.KEY_PRIORITY, 0) // realtime
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setInteger(MediaFormat.KEY_PREPEND_HEADER_TO_SYNC_FRAMES, 1)
            }
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = codec.createInputSurface()
        codec.start()
        this.codec = codec
        encoding = size
        pumping = true
        pump = thread(name = "fuse-screen") { drain(codec, size.width, size.height) }
        return surface
    }

    private fun stopEncoder() {
        pumping = false
        pump?.join(500)
        pump = null
        codec?.let { runCatching { it.stop() }; it.release() }
        codec = null
        encoding = null
    }

    /** Encoder output → the wire, until [active] drops. Runs on its own thread. */
    private fun drain(codec: MediaCodec, width: Int, height: Int) {
        val info = MediaCodec.BufferInfo()
        val transport = ServiceLocator.lanTransport
        try {
            while (pumping) {
                val index = codec.dequeueOutputBuffer(info, 100_000)
                if (index < 0) continue
                val buffer = codec.getOutputBuffer(index)
                val bytes = ByteArray(info.size)
                buffer?.position(info.offset)
                buffer?.get(bytes)
                codec.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                if (bytes.isEmpty()) continue
                val frame = ScreenFrame.newBuilder()
                    .setData(ByteString.copyFrom(bytes))
                    .setConfig(info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0)
                    .setKeyframe(info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0)
                    .setWidth(width)
                    .setHeight(height)
                    .setPtsUs(info.presentationTimeUs)
                transport.broadcast(transport.newEnvelope().setScreenFrame(frame).build())
            }
        } catch (_: IllegalStateException) {
            // The codec was stopped under us: this is the normal way out.
        }
    }

    private fun requestKeyframe() {
        runCatching {
            codec?.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        }
    }

    /** Idempotent: the projection's own onStop calls back in here while we tear down. */
    private fun finish(notifyMac: Boolean) {
        val wasActive = active || projection != null
        active = false
        if (running === this) running = null
        stopEncoder()
        display?.release()
        display = null
        projection?.let { p -> projection = null; runCatching { p.stop() } }
        if (notifyMac && wasActive) {
            runCatching { ServiceLocator.screenShare.send(ScreenControl.Action.STOP) }
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (active) finish(notifyMac = true)
        super.onDestroy()
    }

    private data class CaptureSize(val width: Int, val height: Int, val dpi: Int)

    /**
     * The screen's real size in its current orientation, scaled so its long side is at
     * most [MAX_LONG_SIDE] and both sides are multiples of 16 — what hardware encoders
     * reliably accept.
     */
    private fun captureSize(): CaptureSize {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        getSystemService(WindowManager::class.java).defaultDisplay.getRealMetrics(metrics)
        val scale = minOf(1f, MAX_LONG_SIDE.toFloat() / maxOf(metrics.widthPixels, metrics.heightPixels))
        fun even16(v: Float) = (v.toInt() / 16) * 16
        return CaptureSize(even16(metrics.widthPixels * scale), even16(metrics.heightPixels * scale), metrics.densityDpi)
    }

    private fun startInForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Screen sharing", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val stop = PendingIntent.getService(
            this, 0, Intent(this, ScreenShareService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Sharing your screen with your Mac")
            .setContentText("Everything on screen is visible on the Mac")
            .setOngoing(true)
            .addAction(0, "Stop", stop)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val ACTION_STOP = "com.fuseos.app.screen.STOP"
        private const val EXTRA_CODE = "code"
        private const val EXTRA_DATA = "data"
        private const val CHANNEL_ID = "fuseos_screen"
        private const val NOTIFICATION_ID = 43
        private const val MAX_LONG_SIDE = 1600
        private const val BIT_RATE = 6_000_000
        private const val FPS = 30
        private const val KEYFRAME_SECONDS = 2

        @Volatile private var running: ScreenShareService? = null
            set(value) {
                field = value
                _sharing.value = value != null
            }

        private val _sharing = kotlinx.coroutines.flow.MutableStateFlow(false)
        /** Whether this phone is streaming its screen right now, for the Screen tab. */
        val sharing: kotlinx.coroutines.flow.StateFlow<Boolean> = _sharing

        fun start(context: Context, resultCode: Int, data: Intent) {
            context.startForegroundService(
                Intent(context, ScreenShareService::class.java)
                    .putExtra(EXTRA_CODE, resultCode)
                    .putExtra(EXTRA_DATA, data),
            )
        }

        fun stop(context: Context) {
            if (running == null) return
            context.startService(Intent(context, ScreenShareService::class.java).setAction(ACTION_STOP))
        }

        fun requestKeyframe() {
            running?.requestKeyframe()
        }
    }
}
