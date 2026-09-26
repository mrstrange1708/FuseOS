package com.fuseos.app.actions

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.ui.theme.FuseOSTheme
import com.fuseos.proto.PointerInput
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * The phone as the Mac's trackpad and keyboard.
 *
 * One finger moves the pointer, a tap clicks, a second quick tap double-clicks, a hold then
 * move drags, two fingers scroll, and a two-finger tap right-clicks. The field at the
 * bottom types into whatever has focus on the Mac. The Mac acts on none of it unless its
 * user turned "Let your phone control this Mac" on.
 */
class TrackpadActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent {
            FuseOSTheme {
                // The Surface supplies the content colour; without it text falls back to black.
                Surface(color = MaterialTheme.colorScheme.background) { Trackpad(::send, onDone = ::finish) }
            }
        }
    }

    private fun send(input: PointerInput) {
        val transport = ServiceLocator.lanTransport
        ServiceLocator.appScope.launch(Dispatchers.IO) {
            transport.broadcast(transport.newEnvelope().setPointerInput(input).build())
        }
    }
}

private fun pointer(kind: PointerInput.Kind, dx: Float = 0f, dy: Float = 0f) =
    PointerInput.newBuilder().setKind(kind).setDx(dx).setDy(dy).build()

@Composable
private fun Trackpad(send: (PointerInput) -> Unit, onDone: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Column(
        Modifier
            .fillMaxSize()
            .background(scheme.background)
            .systemBarsPadding()
            .imePadding()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Trackpad", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            Text(
                "Done",
                color = scheme.primary,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onDone).padding(8.dp),
            )
        }
        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(28.dp))
                .background(scheme.surface)
                .border(1.dp, scheme.outlineVariant, RoundedCornerShape(28.dp))
                .pointerInput(Unit) { trackpadGestures(send) },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Move with one finger · tap to click\nTwo fingers to scroll · two-finger tap to right-click\nHold, then move, to drag",
                color = scheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
        KeyRow(send)
        TypingField(send)
    }
}

/** Mac virtual key codes for the keys a trackpad user reaches for. */
@Composable
private fun KeyRow(send: (PointerInput) -> Unit) {
    val keys = listOf("esc" to 53, "tab" to 48, "←" to 123, "→" to 124, "↑" to 126, "↓" to 125, "return" to 36, "delete" to 51)
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        keys.forEach { (label, code) ->
            Text(
                label,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .clickable {
                        send(PointerInput.newBuilder().setKind(PointerInput.Kind.KEY).setKeyCode(code).build())
                    }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            )
        }
    }
}

/**
 * Types on the Mac. The field always holds one sentinel space, so a backspace on an
 * "empty" field still arrives as an edit (and becomes a Mac Delete) instead of vanishing.
 */
@Composable
private fun TypingField(send: (PointerInput) -> Unit) {
    val sentinel = TextFieldValue(" ", selection = TextRange(1))
    var value by remember { mutableStateOf(sentinel) }
    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        if (value.text.isBlank()) {
            Text("Type on your Mac…", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        BasicTextField(
            value = value,
            onValueChange = { next ->
                when {
                    next.text.isEmpty() ->
                        send(PointerInput.newBuilder().setKind(PointerInput.Kind.KEY).setKeyCode(51).build())
                    next.text.length > 1 ->
                        send(PointerInput.newBuilder().setKind(PointerInput.Kind.TEXT).setText(next.text.drop(1)).build())
                }
                value = sentinel
            },
            singleLine = true,
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            textStyle = TextStyle(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * The gesture reader. Deltas are scaled (the pad is small, the Mac's screen is not) and
 * sent as they come; TCP_NODELAY on the channel keeps each one from waiting.
 */
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.trackpadGestures(send: (PointerInput) -> Unit) {
    var lastTapAt = 0L
    awaitEachGesture {
        val first = awaitFirstDown(requireUnconsumed = false)
        val downAt = first.uptimeMillis
        var moved = 0f
        var maxFingers = 1
        var dragging = false
        var last = first.position
        var lastTwo: Offset? = null
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Main)
            val pressed = event.changes.filter { it.pressed }
            maxFingers = maxOf(maxFingers, pressed.size)
            if (pressed.isEmpty()) break
            if (pressed.size >= 2) {
                val centroid = pressed.map { it.position }.reduce { a, b -> a + b } / pressed.size.toFloat()
                lastTwo?.let { previous ->
                    val d = centroid - previous
                    if (abs(d.x) + abs(d.y) > 0.5f) {
                        moved += abs(d.x) + abs(d.y)
                        send(pointer(PointerInput.Kind.SCROLL, d.x * SCROLL_GAIN, d.y * SCROLL_GAIN))
                    }
                }
                lastTwo = centroid
            } else {
                val change = pressed.first()
                val d = change.position - last
                last = change.position
                moved += abs(d.x) + abs(d.y)
                // A still hold becomes a drag: press the Mac's button, then move with it.
                if (!dragging && moved < SLOP && change.uptimeMillis - downAt > HOLD_MS) {
                    dragging = true
                    send(pointer(PointerInput.Kind.DRAG_START))
                }
                if (abs(d.x) + abs(d.y) > 0f) send(pointer(PointerInput.Kind.MOVE, d.x * MOVE_GAIN, d.y * MOVE_GAIN))
            }
            event.changes.forEach { it.consume() }
        }
        val upAt = System.currentTimeMillis()
        when {
            dragging -> send(pointer(PointerInput.Kind.DRAG_END))
            moved < SLOP && maxFingers >= 2 -> send(pointer(PointerInput.Kind.RIGHT_CLICK))
            moved < SLOP -> {
                val double = upAt - lastTapAt < DOUBLE_TAP_MS
                send(pointer(if (double) PointerInput.Kind.DOUBLE_CLICK else PointerInput.Kind.CLICK))
                lastTapAt = if (double) 0L else upAt
            }
        }
    }
}

private const val MOVE_GAIN = 1.6f
private const val SCROLL_GAIN = 1.2f
private const val SLOP = 18f
private const val HOLD_MS = 420L
private const val DOUBLE_TAP_MS = 320L
