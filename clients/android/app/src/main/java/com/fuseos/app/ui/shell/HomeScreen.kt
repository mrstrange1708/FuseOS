package com.fuseos.app.ui.shell

import com.fuseos.app.ui.components.glassCard
import androidx.compose.foundation.background
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.spring
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import com.fuseos.app.ui.theme.Amber
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.runtime.getValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import com.fuseos.app.ui.components.FusePrimaryButton
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.clipboard.SyncLatency
import com.fuseos.app.core.ConnectStage
import com.fuseos.app.file.TransferProgress
import com.fuseos.app.ui.dashboard.DashboardViewModel

/**
 * The landing screen: link status first, then the last few clips.
 *
 * Status leads because every question a user brings to this app ("did it send?", "why is
 * nothing happening?") is really a question about the link. Recent clips are the proof
 * that it is working, so they sit directly underneath rather than on their own tab.
 */
@Composable
fun HomeScreen(
    state: DashboardViewModel.UiState,
    history: List<ClipEntry>,
    selfBattery: Int?,
    peerBattery: (String) -> Int?,
    onCopy: (ClipEntry) -> Unit,
    onSeeAll: () -> Unit,
    peerName: String?,
    transfers: List<TransferProgress>,
    onSendFile: () -> Unit,
    onCancelTransfer: (String) -> Unit,
    onOpenTransfer: (String) -> Unit,
    latency: SyncLatency? = null,
    macStatus: com.fuseos.app.core.PeerStatus? = null,
    onOpenLinkOnMac: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val connect = state.connect
    val peer = state.peers.firstOrNull { it.id == connect.peerId }
    val linked = connect.stage == ConnectStage.Connected

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        LinkHero(
            selfName = state.selfDevice?.name ?: "This phone",
            peerName = peer?.name ?: state.peers.firstOrNull()?.name,
            stage = connect.stage,
            peerBattery = macStatus?.battery ?: peer?.let { peerBattery(it.id) },
            peerCharging = macStatus?.charging == true,
            latency = latency,
            // The newest clip crossed the link: from here when this phone copied it.
            crossing = history.firstOrNull()?.let { Crossing(it.id, toMac = it.fromSelf) },
            streamToMac = transfers.firstOrNull { it.state == TransferProgress.State.Active }?.outgoing,
        )

        Panel(title = "Files") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = if (linked) 0.10f else 0.04f))
                    .clickable(enabled = linked, onClick = onSendFile)
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconTile(
                    Icons.Filled.UploadFile,
                    tint = if (linked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        if (linked) "Send a file to ${peer?.name ?: "your Mac"}" else "Send a file",
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        if (linked) "It lands in the Mac's Downloads." else "Link your Mac first.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            transfers.take(4).forEach { transfer ->
                TransferListRow(transfer, peerName, onCancelTransfer, onOpenTransfer)
            }
            // Handoff, phone → Mac: the link on this phone's clipboard, in the Mac's browser.
            // Enabled even unlinked, so a tap is answered (in the island) rather than ignored.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = if (linked) 0.10f else 0.04f))
                    .clickable(onClick = onOpenLinkOnMac)
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconTile(
                    Icons.Filled.OpenInBrowser,
                    tint = if (linked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "Open copied link on ${peer?.name ?: "your Mac"}",
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "Copy a link here, tap, and it opens in the Mac's browser.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Panel(
            title = "Clipboard",
            action = {
                Text(
                    "See all",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onSeeAll).padding(4.dp),
                )
            },
        ) {
            if (history.isEmpty()) {
                Text(
                    "Copy something on either device and it shows up here.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(4.dp),
                )
            } else {
                // Five proves sync is alive without turning Home into History.
                history.take(5).forEach { entry -> ClipListRow(entry, peerName, onCopy) }
            }
        }
        Spacer(Modifier.height(110.dp)) // clears the floating nav bar
    }
}

/**
 * The top of Home: this phone and the Mac, joined by the filament a spark runs along while
 * they are linked. The same card leads the Mac's Home — it answers the only question people
 * open the app to ask, so it is the one showy thing here.
 */
@Composable
private fun LinkHero(
    selfName: String,
    peerName: String?,
    stage: ConnectStage,
    peerBattery: Int?,
    peerCharging: Boolean,
    latency: SyncLatency?,
    crossing: Crossing?,
    streamToMac: Boolean?,
) {
    val linked = stage == ConnectStage.Connected
    // Which end last caught something, so it can take the hit.
    var caught by remember { mutableStateOf<Pair<Boolean, Any>?>(null) }
    val ember = MaterialTheme.colorScheme.primary
    val pill = when (stage) {
        ConnectStage.Connected -> "Linked · direct"
        ConnectStage.Connecting -> "Connecting"
        ConnectStage.DifferentNetwork -> "Different networks"
        ConnectStage.PeerOffline -> "Mac offline"
        ConnectStage.Alone -> "Waiting for a Mac"
    }
    val detail = when (stage) {
        ConnectStage.Connected -> "Clipboard, files and notifications move straight over your Wi-Fi."
        ConnectStage.Connecting -> "Finding ${peerName ?: "your Mac"} on this Wi-Fi…"
        ConnectStage.DifferentNetwork -> "Put both devices on the same Wi-Fi."
        ConnectStage.PeerOffline -> "Open FuseOS on ${peerName ?: "your Mac"} to link it."
        ConnectStage.Alone -> "Sign in on your Mac with this account."
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(24.dp)
            // The website's glowing edge: lit while linked, the one warm outline on Home.
            .border(
                1.dp,
                Brush.linearGradient(
                    listOf(ember.copy(alpha = if (linked) 0.7f else 0.1f), Color.Transparent, Amber.copy(alpha = if (linked) 0.45f else 0.05f)),
                ),
                RoundedCornerShape(24.dp),
            )
            .padding(horizontal = 18.dp, vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Endpoint(Icons.Filled.Smartphone, selfName, lit = true, catchKey = caught?.takeIf { !it.first })
            Filament(
                linked,
                crossing,
                streamToMac,
                onArrive = { toMac -> caught = toMac to Any() },
                modifier = Modifier.weight(1f).height(24.dp).padding(horizontal = 4.dp),
            )
            Endpoint(Icons.Filled.Computer, peerName ?: "Your Mac", lit = linked, catchKey = caught?.takeIf { it.first })
        }
        Spacer(Modifier.height(16.dp))
        StatusPill(pill, linked)
        Spacer(Modifier.height(8.dp))
        Text(
            peerName ?: "No Mac yet",
            // Ember to amber, like the website's headline — only when there is a link to celebrate.
            style = if (linked) {
                MaterialTheme.typography.titleLarge.copy(brush = Brush.linearGradient(listOf(ember, Amber)))
            } else {
                MaterialTheme.typography.titleLarge
            },
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        val facts = listOfNotNull(
            peerBattery?.let { if (peerCharging) "⚡ Charging $it%" else "Battery $it%" },
            // The PRD's yardstick — p95 under 300 ms — shown where people look.
            latency?.takeIf { linked }?.let { "Sync ${it.lastMs} ms · p95 ${it.p95Ms} ms" },
        )
        if (facts.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text(
                facts.joinToString("  ·  "),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Endpoint(icon: ImageVector, name: String, lit: Boolean, catchKey: Any? = null) {
    val bump = remember { Animatable(1f) }
    LaunchedEffect(catchKey) {
        if (catchKey == null) return@LaunchedEffect
        bump.snapTo(1.16f)
        bump.animateTo(1f, spring(dampingRatio = 0.35f, stiffness = 500f))
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(92.dp)) {
        Box(
            Modifier
                .size(58.dp)
                .scale(bump.value)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = if (lit) 0.16f else 0.06f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (lit) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(26.dp),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            name,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Something crossed the link: which item (so it plays once), and which way. */
data class Crossing(val key: Any, val toMac: Boolean)

/**
 * The line between the devices, driven by what actually moves: a comet with an amber tail
 * for each clip, in the direction it went; beads streaming the whole time a file is in
 * flight. Idle, it rests — a spark that loops by itself says nothing. Not linked: a dim
 * dashed gap.
 */
@Composable
private fun Filament(
    linked: Boolean,
    crossing: Crossing?,
    streamToMac: Boolean?,
    onArrive: (toMac: Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val ember = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val spark = remember { Animatable(0f) }
    var toMac by remember { mutableStateOf(true) }
    // What was already there when Home opened is history, not news.
    val seen = remember { crossing?.key }
    LaunchedEffect(crossing?.key) {
        val c = crossing ?: return@LaunchedEffect
        if (c.key == seen || !linked) return@LaunchedEffect
        toMac = c.toMac
        spark.snapTo(0f)
        spark.animateTo(1f, tween(620, easing = FastOutSlowInEasing))
        onArrive(c.toMac)
        spark.snapTo(0f)
    }
    val bead = if (streamToMac != null) {
        rememberInfiniteTransition(label = "stream").animateFloat(
            0f, 1f, infiniteRepeatable(tween(1100, easing = LinearEasing), RepeatMode.Restart), label = "bead",
        ).value
    } else {
        null
    }
    Canvas(modifier) {
        val y = size.height / 2
        val w = size.width
        if (!linked) {
            drawLine(
                muted.copy(alpha = 0.4f), Offset(0f, y), Offset(w, y),
                strokeWidth = 1.5.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 6.dp.toPx())),
            )
            return@Canvas
        }
        drawLine(
            Brush.horizontalGradient(listOf(ember.copy(alpha = 0.15f), ember.copy(alpha = 0.5f), ember.copy(alpha = 0.15f))),
            Offset(0f, y), Offset(w, y), strokeWidth = 2.dp.toPx(),
        )
        if (bead != null && streamToMac != null) {
            repeat(3) { i ->
                val t = (bead + i / 3f) % 1f
                val x = if (streamToMac) t * w else (1 - t) * w
                // Fade in and out at the ends so beads appear to leave one device and enter the other.
                val a = kotlin.math.sin(t * Math.PI).toFloat()
                drawCircle(Amber.copy(alpha = a), radius = 3.dp.toPx(), center = Offset(x, y))
            }
        }
        val t = spark.value
        if (t > 0f) {
            val x = if (toMac) t * w else (1 - t) * w
            val tail = 64.dp.toPx() * (1 - kotlin.math.abs(0.5f - t))
            val from = Offset(if (toMac) x - tail else x + tail, y)
            drawLine(
                Brush.linearGradient(listOf(Color.Transparent, Amber), start = from, end = Offset(x, y)),
                from, Offset(x, y), strokeWidth = 3.dp.toPx(), cap = StrokeCap.Round,
            )
            drawCircle(ember.copy(alpha = 0.28f), radius = 11.dp.toPx(), center = Offset(x, y))
            drawCircle(Amber, radius = 4.5.dp.toPx(), center = Offset(x, y))
        }
    }
}

/**
 * Sharing this phone's screen to the Mac. The Mac can ask for it too; either way Android's
 * own consent dialog decides, every session. View only — the Mac cannot tap anything.
 */
@Composable
fun ScreenShareScreen(
    linked: Boolean,
    sharing: Boolean,
    peerName: String?,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onTrackpad: () -> Unit = {},
    onSidecar: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val mac = peerName ?: "your Mac"
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(88.dp)
                .clip(RoundedCornerShape(26.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = if (sharing) 0.22f else 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.ScreenShare,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(36.dp),
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            if (sharing) "Sharing this screen" else "Share this screen",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            when {
                sharing -> "$mac can see everything on this screen. Stop any time here or from the notification."
                linked -> "Show this phone live on $mac, straight over your Wi-Fi — nothing goes through the internet."
                else -> "Link your Mac first — sharing runs over the same direct connection."
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        FusePrimaryButton(
            text = if (sharing) "Stop sharing" else "Share screen",
            onClick = if (sharing) onStop else onStart,
            enabled = sharing || linked,
        )
        Spacer(Modifier.height(12.dp))
        androidx.compose.material3.OutlinedButton(
            onClick = onTrackpad,
            enabled = linked,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) { Text("Use as trackpad for $mac") }
        Spacer(Modifier.height(10.dp))
        androidx.compose.material3.OutlinedButton(
            onClick = onSidecar,
            enabled = linked,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) { Text("Use as a second display for $mac") }
        Spacer(Modifier.height(100.dp))
    }
}
