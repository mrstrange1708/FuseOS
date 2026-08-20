package com.fuseos.app.ui.island

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.SouthWest
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.clipboard.PendingClip
import com.fuseos.app.ui.theme.FuseOSTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The island: a capsule that drops from under the status bar, says one thing, and leaves.
 *
 * The Android twin of `ClipIsland` on macOS, and it exists for the same reason — sync is
 * invisible by nature, so without a signal the user cannot tell "it worked" from "it is
 * broken". It is drawn in a `TYPE_APPLICATION_OVERLAY` window rather than inside the app
 * because the moment worth confirming is always the moment the user is in *another* app.
 *
 * Two shapes, one component:
 *  - [prompt] — "Copied · tap to send". The capsule is the send button.
 *  - [status] — "Sent" / "From your Mac". Auto-dismisses; a tap only dismisses it early.
 *
 * The window is `FLAG_NOT_FOCUSABLE`: it must never take focus from whatever the user is
 * typing into. That also means it cannot read the clipboard itself — content is captured
 * by [com.fuseos.app.capture.CaptureActivity], which briefly can, and handed here.
 */
class ClipIsland(context: Context) {

    private val appContext = context.applicationContext
    private val windowManager = appContext.getSystemService(WindowManager::class.java)
    private val scope = CoroutineScope(Dispatchers.Main.immediate)

    private var host: OverlayHost? = null
    private var dismissJob: Job? = null

    /** What the island is showing right now; null once it has left the screen. */
    private var content by mutableStateOf<IslandContent?>(null)

    /**
     * Offers a captured clip. Tapping the capsule runs [onSend], which swaps the island
     * into its confirmation shape rather than dismissing it — the user gets to see that
     * the tap did something.
     */
    fun prompt(clip: PendingClip, onSend: (PendingClip) -> Unit) {
        show(
            IslandContent(
                title = "Copied",
                subtitle = clip.preview(),
                action = "Tap to send",
                thumbnail = clip.imageBytes,
                icon = IslandIcon.Copy,
                // No confirmation is set here: sending records the clip, which emits on
                // ClipboardSync.events, which swaps this island's content in place. One
                // source of truth for "it went", and the capsule morphs instead of
                // collapsing and re-opening.
                onTap = { onSend(clip) },
            ),
            // A prompt waits on a person, so it lingers; a status is just an ack.
            visibleMs = PROMPT_VISIBLE_MS,
        )
    }

    /** Shows a clip that has already moved, in whichever direction. */
    fun clip(entry: ClipEntry) {
        val incoming = !entry.fromSelf
        status(
            title = if (incoming) "From your Mac" else "Sent",
            subtitle = if (entry.isImage) {
                if (incoming) "Image on your clipboard" else "Image sent"
            } else {
                entry.text.orEmpty().singleLine()
            },
            thumbnail = entry.imageBytes,
            icon = if (incoming) IslandIcon.Incoming else IslandIcon.Sent,
        )
    }

    fun status(
        title: String,
        subtitle: String,
        thumbnail: ByteArray? = null,
        icon: IslandIcon = IslandIcon.Sent,
    ) {
        show(
            IslandContent(
                title = title,
                subtitle = subtitle,
                action = null,
                thumbnail = thumbnail,
                icon = icon,
                onTap = { hide() },
            ),
            visibleMs = STATUS_VISIBLE_MS,
        )
    }

    fun hide() {
        scope.launch {
            dismissJob?.cancel()
            dismissJob = null
            content = null
            // The window outlives the collapse animation, or the capsule would vanish
            // mid-flight instead of folding back into its circle.
            delay(EXIT_MS)
            if (content == null) tearDown()
        }
    }

    private fun show(next: IslandContent, visibleMs: Long) {
        scope.launch {
            if (!canDraw()) return@launch
            ensureWindow()
            // A newer clip replaces the older one rather than queueing: a backlog of stale
            // animations is noise, and only the newest clip is still true.
            content = next
            dismissJob?.cancel()
            dismissJob = launch {
                delay(visibleMs)
                hide()
            }
        }
    }

    /**
     * True once the user has granted "Display over other apps". Without it `addView`
     * throws, so this is a precondition, not a nicety — see [overlaySettingsIntent].
     */
    fun canDraw(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(appContext)

    private fun ensureWindow() {
        if (host != null) return
        val host = OverlayHost(appContext)
        val view = ComposeView(appContext).apply {
            setContent { FuseOSTheme { IslandSurface(content) } }
        }
        host.attach(view)
        runCatching { windowManager.addView(view, layoutParams()) }
            .onFailure { host.detach(); return }
        this.host = host
    }

    private fun tearDown() {
        val host = host ?: return
        this.host = null
        runCatching { windowManager.removeView(host.view) }
        host.detach()
    }

    private fun layoutParams() = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        },
        // NOT_FOCUSABLE keeps the keyboard and the app underneath exactly as they were;
        // NOT_TOUCH_MODAL lets every touch outside the capsule fall through to them.
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        // FLAG_LAYOUT_NO_LIMITS measures y from the true top of the screen, so the status
        // bar has to be stepped over explicitly. A fixed offset does not survive contact
        // with real hardware: it hid the title behind the clock on a Realme, whose status
        // bar is half again as tall as a Pixel's. Ask the platform instead.
        y = statusBarHeight() + (TOP_GAP_DP * appContext.resources.displayMetrics.density).toInt()
    }

    /**
     * Height of the status bar in pixels, including whatever the OEM does with a notch or
     * punch-hole. Falls back to a sane guess on the phones that do not publish it.
     */
    private fun statusBarHeight(): Int {
        val resources = appContext.resources
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        if (id > 0) return resources.getDimensionPixelSize(id)
        return (24 * resources.displayMetrics.density).toInt()
    }

    /** Where to send the user when [canDraw] is false. */
    companion object {
        fun overlaySettingsIntent(context: Context) = android.content.Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            android.net.Uri.parse("package:${context.packageName}"),
        )

        private const val PROMPT_VISIBLE_MS = 6_000L
        private const val STATUS_VISIBLE_MS = 2_400L
        private const val EXIT_MS = 260L
        /** Breathing room under the status bar — and under an OEM island, if the
         *  phone has one of its own sitting in exactly this spot. */
        private const val TOP_GAP_DP = 10f
    }
}

enum class IslandIcon { Copy, Sent, Incoming }

/** One frame of island content. Immutable, so swapping it re-runs the entry animation. */
private data class IslandContent(
    val title: String,
    val subtitle: String,
    val action: String?,
    val thumbnail: ByteArray?,
    val icon: IslandIcon,
    val onTap: () -> Unit,
)

private fun PendingClip.preview(): String =
    if (imageBytes != null) "Image · ${imageBytes.size / 1024} KB" else text.orEmpty().singleLine()

/** Newlines would render a one-line preview as a stray fragment. */
private fun String.singleLine(): String = replace('\n', ' ').trim()

/**
 * Circle → capsule → circle.
 *
 * The whole point of the shape: it arrives as a dot, opens only as wide as it needs to be,
 * and folds back into a dot on the way out. Corner radius stays at half the height
 * throughout, so it is never anything but a capsule mid-animation.
 */
@Composable
private fun IslandSurface(content: IslandContent?) {
    // Held separately from `content` so the copy stays on screen while it collapses,
    // instead of blanking a frame before the exit animation has run.
    var shown by androidx.compose.runtime.remember { mutableStateOf(content) }
    LaunchedEffect(content) { if (content != null) shown = content }

    val open = content != null
    val width by animateDpAsState(
        targetValue = if (open) 340.dp else HEIGHT,
        animationSpec = spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMediumLow),
        label = "island-width",
    )
    val drop by animateDpAsState(
        targetValue = if (open) 0.dp else (-HEIGHT / 2),
        animationSpec = spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow),
        label = "island-drop",
    )
    // Text fades a beat behind the capsule so it never renders squeezed into the circle.
    val textAlpha by animateFloatAsState(
        targetValue = if (open) 1f else 0f,
        animationSpec = tween(durationMillis = if (open) 220 else 90, delayMillis = if (open) 90 else 0),
        label = "island-text",
    )
    val shellAlpha by animateFloatAsState(
        targetValue = if (open) 1f else 0f,
        animationSpec = tween(durationMillis = if (open) 140 else 200),
        label = "island-shell",
    )

    val body = shown ?: return
    val scheme = MaterialTheme.colorScheme

    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Row(
            modifier = Modifier
                // offset, not padding: the capsule starts *above* its slot and slides
                // down into it, and padding rejects a negative value outright.
                .offset(y = drop)
                .width(width)
                .height(HEIGHT)
                .alpha(shellAlpha)
                .clip(RoundedCornerShape(HEIGHT / 2))
                // Opaque, not translucent: this floats over arbitrary app content, and a
                // blur we cannot do on Android would just leave text unreadable.
                .background(scheme.surface)
                .border(1.dp, scheme.outlineVariant, RoundedCornerShape(HEIGHT / 2))
                .clickable(onClick = body.onTap)
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Badge(body.icon)

            Box(Modifier.weight(1f).alpha(textAlpha)) {
                androidx.compose.foundation.layout.Column {
                    Text(
                        text = body.title,
                        style = MaterialTheme.typography.labelLarge,
                        color = scheme.onSurface,
                        maxLines = 1,
                    )
                    Text(
                        text = body.action ?: body.subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (body.action != null) scheme.primary else scheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            body.thumbnail?.let { bytes ->
                Thumbnail(bytes, Modifier.alpha(textAlpha))
            } ?: Spacer(Modifier.width(2.dp))
        }
    }
}

/** The logo mark on the left: an ember disc with the direction of travel inside it. */
@Composable
private fun Badge(icon: IslandIcon) {
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .size(40.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(scheme.primary.copy(alpha = 0.14f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = when (icon) {
                IslandIcon.Copy -> Icons.Rounded.ContentCopy
                IslandIcon.Sent -> Icons.Rounded.Check
                IslandIcon.Incoming -> Icons.Rounded.SouthWest
            },
            contentDescription = null,
            tint = scheme.primary,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun Thumbnail(bytes: ByteArray, modifier: Modifier = Modifier) {
    val bitmap = androidx.compose.runtime.remember(bytes) {
        runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    } ?: return
    Image(
        bitmap = bitmap.asImageBitmap(),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = modifier.size(36.dp).clip(RoundedCornerShape(10.dp)),
    )
}

private val HEIGHT = 56.dp
