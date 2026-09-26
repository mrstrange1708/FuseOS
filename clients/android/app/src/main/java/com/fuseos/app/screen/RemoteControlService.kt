package com.fuseos.app.screen

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.fuseos.app.BuildConfig
import com.fuseos.proto.RemoteInput

/**
 * Lets the Mac drive this phone while its screen is mirrored: taps, swipes, back, home.
 *
 * Android has exactly one sanctioned way for an app to act on other apps' UI, and this is
 * it — an AccessibilityService the user enables by hand in Settings. Coordinates arrive
 * normalised (0–1 of the screen), because the Mac only knows the mirrored image's shape.
 */
class RemoteControlService : AccessibilityService() {
    private var debugReceiver: BroadcastReceiver? = null

    override fun onServiceConnected() {
        instance = this
        // Debug builds only: drive it from adb, e.g.
        //   adb shell am broadcast -a com.fuseos.app.debug.REMOTE --es op tap --ef x 0.5 --ef y 0.3
        if (BuildConfig.DEBUG) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.getStringExtra("op")) {
                        "tap" -> tap(intent.getFloatExtra("x", 0.5f), intent.getFloatExtra("y", 0.5f))
                        "swipe" -> swipe(
                            intent.getFloatExtra("x", 0.5f), intent.getFloatExtra("y", 0.8f),
                            intent.getFloatExtra("x2", 0.5f), intent.getFloatExtra("y2", 0.2f),
                        )
                        "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
                        "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
                        "text" -> perform(
                            RemoteInput.newBuilder().setKind(RemoteInput.Kind.TEXT)
                                .setText(intent.getStringExtra("text").orEmpty()).build(),
                        )
                        "delete" -> perform(RemoteInput.newBuilder().setKind(RemoteInput.Kind.KEY).setKeyCode(67).build())
                    }
                }
            }
            val filter = IntentFilter("com.fuseos.app.debug.REMOTE")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, RECEIVER_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
            debugReceiver = receiver
        }
    }

    override fun onUnbind(intent: Intent?): Boolean {
        debugReceiver?.let { unregisterReceiver(it) }
        debugReceiver = null
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    /** One input from the Mac. The caller has already checked the screen is being shared. */
    fun perform(input: RemoteInput) {
        when (input.kind) {
            RemoteInput.Kind.TAP -> tap(input.x, input.y)
            RemoteInput.Kind.LONG_PRESS -> stroke(input.x, input.y, input.x, input.y, LONG_PRESS_MS)
            RemoteInput.Kind.SWIPE -> swipe(
                input.x, input.y, input.x2, input.y2,
                input.durationMs.toLong().coerceIn(MIN_SWIPE_MS, MAX_SWIPE_MS),
            )
            RemoteInput.Kind.BACK -> performGlobalAction(GLOBAL_ACTION_BACK)
            RemoteInput.Kind.HOME -> performGlobalAction(GLOBAL_ACTION_HOME)
            RemoteInput.Kind.RECENTS -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            RemoteInput.Kind.TEXT -> type(input.text)
            RemoteInput.Kind.KEY -> key(input.keyCode)
            else -> Unit
        }
    }

    /** Appends to the focused field — the one piece of other apps' UI this ever reads. */
    private fun type(text: String) {
        val field = focusedField() ?: return
        val current = field.text?.toString().takeUnless { field.isShowingHintText }.orEmpty()
        setText(field, current + text)
    }

    private fun key(code: Int) {
        val field = focusedField()
        when (code) {
            KEYCODE_DEL -> field?.let {
                val current = it.text?.toString().takeUnless { _ -> it.isShowingHintText }.orEmpty()
                if (current.isNotEmpty()) setText(it, current.dropLast(1))
            }
            KEYCODE_ENTER -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                field?.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
            }
        }
    }

    private fun focusedField(): AccessibilityNodeInfo? =
        rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.takeIf { it.isEditable }

    private fun setText(field: AccessibilityNodeInfo, text: String) {
        field.performAction(
            AccessibilityNodeInfo.ACTION_SET_TEXT,
            Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) },
        )
    }

    fun tap(x: Float, y: Float) = stroke(x, y, x, y, TAP_MS)

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = SWIPE_MS) =
        stroke(x1, y1, x2, y2, durationMs)

    private fun stroke(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long) {
        val (w, h) = screenSize()
        val path = Path().apply {
            moveTo(x1.coerceIn(0f, 1f) * w, y1.coerceIn(0f, 1f) * h)
            lineTo(x2.coerceIn(0f, 1f) * w, y2.coerceIn(0f, 1f) * h)
        }
        dispatchGesture(
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
                .build(),
            null,
            null,
        )
    }

    private fun screenSize(): Pair<Float, Float> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        getSystemService(WindowManager::class.java).defaultDisplay.getRealMetrics(metrics)
        return metrics.widthPixels.toFloat() to metrics.heightPixels.toFloat()
    }

    companion object {
        private const val TAP_MS = 40L
        private const val SWIPE_MS = 250L
        private const val LONG_PRESS_MS = 650L
        private const val MIN_SWIPE_MS = 60L
        private const val MAX_SWIPE_MS = 2_000L
        private const val KEYCODE_DEL = 67
        private const val KEYCODE_ENTER = 66

        @Volatile
        var instance: RemoteControlService? = null
            private set
    }
}
