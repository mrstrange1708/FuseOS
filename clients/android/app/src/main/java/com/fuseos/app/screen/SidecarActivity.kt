package com.fuseos.app.screen

import android.annotation.SuppressLint
import android.content.pm.ActivityInfo
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.fuseos.app.data.ServiceLocator
import com.fuseos.proto.Envelope
import com.fuseos.proto.ScreenFrame
import com.fuseos.proto.SidecarControl
import com.fuseos.proto.SidecarInput
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Sidecar: this phone as a second display for the Mac.
 *
 * Full-screen and landscape. It asks the Mac for a display of exactly this screen's shape,
 * decodes the H.264 the Mac streams (hardware MediaCodec, straight onto a SurfaceView), and
 * sends touches back: a tap clicks, a drag drags, two fingers scroll, a long press
 * right-clicks. Leaving the screen ends it, and the Mac removes the display.
 */
class SidecarActivity : ComponentActivity(), SurfaceHolder.Callback {
    private val frames = LinkedBlockingQueue<ScreenFrame>(90)
    @Volatile private var surface: Surface? = null
    @Volatile private var running = false
    private var decoderThread: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        val view = SurfaceView(this)
        view.holder.addCallback(this)
        setContentView(view)
        attachTouches(view)

        lifecycleScope.launch {
            ServiceLocator.lanTransport.incoming.collect { envelope ->
                when (envelope.bodyCase) {
                    Envelope.BodyCase.SIDECAR_FRAME -> if (!frames.offer(envelope.sidecarFrame)) {
                        // Behind: drop the backlog and ask for a keyframe to rejoin cleanly.
                        frames.clear()
                        send(SidecarControl.Action.KEYFRAME)
                    }
                    Envelope.BodyCase.SIDECAR_CONTROL ->
                        if (envelope.sidecarControl.action == SidecarControl.Action.STOP) {
                            Toast.makeText(this@SidecarActivity, "Your Mac ended the second display", Toast.LENGTH_SHORT).show()
                            finish()
                        }
                    else -> Unit
                }
            }
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) = Unit

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (width < height || running) return // wait for landscape
        surface = holder.surface
        running = true
        decoderThread = thread(name = "fuse-sidecar") { decode() }
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        send(SidecarControl.Action.START, width, height, metrics.densityDpi)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) = end()

    override fun onStop() {
        super.onStop()
        end()
        finish()
    }

    private fun end() {
        if (!running) return
        running = false
        send(SidecarControl.Action.STOP)
        decoderThread?.interrupt()
        decoderThread = null
    }

    /** Frames → hardware decoder → the SurfaceView. Created at the first parameter sets. */
    private fun decode() {
        var codec: MediaCodec? = null
        val info = MediaCodec.BufferInfo()
        try {
            while (running) {
                val frame = frames.poll(100, TimeUnit.MILLISECONDS) ?: continue
                if (codec == null) {
                    // Only a keyframe (which carries SPS/PPS) can start a decoder.
                    if (!frame.keyframe) continue
                    codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
                        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, frame.width, frame.height)
                        format.setInteger(MediaFormat.KEY_PRIORITY, 0)
                        configure(format, surface, null, 0)
                        start()
                    }
                }
                val input = codec.dequeueInputBuffer(10_000)
                if (input >= 0) {
                    val buffer = codec.getInputBuffer(input) ?: continue
                    val bytes = frame.data.toByteArray()
                    buffer.clear()
                    buffer.put(bytes)
                    codec.queueInputBuffer(input, 0, bytes.size, frame.ptsUs, 0)
                }
                while (true) {
                    val output = codec.dequeueOutputBuffer(info, 0)
                    if (output < 0) break
                    codec.releaseOutputBuffer(output, true)
                }
            }
        } catch (_: InterruptedException) {
        } catch (_: IllegalStateException) {
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
        }
    }

    private fun send(action: SidecarControl.Action, width: Int = 0, height: Int = 0, dpi: Int = 0) {
        val transport = ServiceLocator.lanTransport
        ServiceLocator.appScope.launch(Dispatchers.IO) {
            val control = SidecarControl.newBuilder().setAction(action).setWidth(width).setHeight(height).setDpi(dpi)
            transport.broadcast(transport.newEnvelope().setSidecarControl(control).build())
        }
    }

    private fun input(kind: SidecarInput.Kind, x: Float, y: Float, dx: Float = 0f, dy: Float = 0f) {
        val transport = ServiceLocator.lanTransport
        ServiceLocator.appScope.launch(Dispatchers.IO) {
            val message = SidecarInput.newBuilder().setKind(kind).setX(x).setY(y).setDx(dx).setDy(dy)
            transport.broadcast(transport.newEnvelope().setSidecarInput(message).build())
        }
    }

    /** Taps click, drags drag, two fingers scroll, a still long press right-clicks. */
    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouches(view: SurfaceView) {
        var downX = 0f
        var downY = 0f
        var downAt = 0L
        var dragging = false
        var twoFinger = false
        var lastScrollY = 0f
        var lastScrollX = 0f
        view.setOnTouchListener { v, e ->
            val w = v.width.toFloat().coerceAtLeast(1f)
            val h = v.height.toFloat().coerceAtLeast(1f)
            val x = (e.x / w).coerceIn(0f, 1f)
            val y = (e.y / h).coerceIn(0f, 1f)
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.x; downY = e.y; downAt = e.eventTime
                    dragging = false; twoFinger = false
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    twoFinger = true
                    lastScrollX = e.getX(0); lastScrollY = e.getY(0)
                }
                MotionEvent.ACTION_MOVE -> when {
                    twoFinger -> {
                        val dx = e.getX(0) - lastScrollX
                        val dy = e.getY(0) - lastScrollY
                        lastScrollX = e.getX(0); lastScrollY = e.getY(0)
                        input(SidecarInput.Kind.SCROLL, x, y, dx, dy)
                    }
                    !dragging && abs(e.x - downX) + abs(e.y - downY) > SLOP -> {
                        dragging = true
                        input(SidecarInput.Kind.DOWN, downX / w, downY / h)
                        input(SidecarInput.Kind.MOVE, x, y)
                    }
                    dragging -> input(SidecarInput.Kind.MOVE, x, y)
                }
                MotionEvent.ACTION_UP -> when {
                    twoFinger -> Unit
                    dragging -> input(SidecarInput.Kind.UP, x, y)
                    e.eventTime - downAt > LONG_PRESS_MS -> input(SidecarInput.Kind.RIGHT_CLICK, x, y)
                    else -> input(SidecarInput.Kind.TAP, x, y)
                }
            }
            true
        }
    }

    private companion object {
        const val SLOP = 24f
        const val LONG_PRESS_MS = 500L
    }
}
