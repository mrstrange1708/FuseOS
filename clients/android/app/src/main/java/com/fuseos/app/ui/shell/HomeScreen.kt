package com.fuseos.app.ui.shell

import com.fuseos.app.ui.components.glassCard
import androidx.compose.foundation.background
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Smartphone
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import com.fuseos.app.ui.components.FusePrimaryButton
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fuseos.app.clipboard.ClipEntry
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
    modifier: Modifier = Modifier,
) {
    val connect = state.connect
    val peer = state.peers.firstOrNull { it.id == connect.peerId }

    val linked = connect.stage == ConnectStage.Connected

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        LinkHero(
            selfName = state.selfDevice?.name ?: "This phone",
            peerName = peer?.name ?: state.peers.firstOrNull()?.name,
            stage = connect.stage,
            peerBattery = peer?.let { peerBattery(it.id) },
        )
        Spacer(Modifier.height(22.dp))

        Text("Files", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(10.dp))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .glassCard(18.dp)
                .clickable(enabled = linked, onClick = onSendFile)
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(42.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = if (linked) 0.16f else 0.07f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.UploadFile,
                    contentDescription = null,
                    tint = if (linked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.size(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    if (linked) "Send a file to ${peer?.name ?: "your Mac"}" else "Send a file",
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    if (linked) "It lands in the Mac's Downloads." else "Link your Mac first.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        transfers.forEach { transfer ->
            TransferRow(transfer, peerName, onCancelTransfer, onOpenTransfer)
            Spacer(Modifier.height(8.dp))
        }

        Spacer(Modifier.height(14.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Recent", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            Text(
                "See all",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable(onClick = onSeeAll),
            )
        }
        Spacer(Modifier.height(10.dp))

        if (history.isEmpty()) {
            Text(
                "Nothing yet. Copy something on either device.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            // Three is enough to prove sync is alive without turning home into the
            // history tab; the rest is one tap away.
            history.take(3).forEach { entry ->
                RecentRow(entry, peerName, onCopy)
                Spacer(Modifier.height(8.dp))
            }
        }
        Spacer(Modifier.height(120.dp)) // clears the floating nav bar
    }
}

/**
 * The top of Home: this phone and the Mac, joined by the filament a spark runs along while
 * they are linked. The same card leads the Mac's Home — it answers the only question people
 * open the app to ask.
 */
@Composable
private fun LinkHero(selfName: String, peerName: String?, stage: ConnectStage, peerBattery: Int?) {
    val linked = stage == ConnectStage.Connected
    val title = when (stage) {
        ConnectStage.Connected -> "Linked to ${peerName ?: "your Mac"}"
        ConnectStage.Connecting -> "Connecting…"
        ConnectStage.DifferentNetwork -> "Different networks"
        ConnectStage.PeerOffline -> "${peerName ?: "Your Mac"} is offline"
        ConnectStage.Alone -> "No Mac yet"
    }
    val detail = when (stage) {
        ConnectStage.Connected -> "Clipboard, files and notifications move directly over your Wi-Fi."
        ConnectStage.Connecting -> "Finding ${peerName ?: "your Mac"} on your Wi-Fi."
        ConnectStage.DifferentNetwork -> "Join the same Wi-Fi as ${peerName ?: "your Mac"}."
        ConnectStage.PeerOffline -> "Open FuseOS on ${peerName ?: "your Mac"} to link it."
        ConnectStage.Alone -> "Sign in on your Mac with this account."
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(24.dp)
            .padding(horizontal = 20.dp, vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Endpoint(Icons.Filled.Smartphone, selfName, lit = true)
            Filament(linked, Modifier.weight(1f).height(24.dp).padding(horizontal = 6.dp))
            Endpoint(Icons.Filled.Computer, peerName ?: "Your Mac", lit = linked)
        }
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(4.dp))
        Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (peerBattery != null) {
            Spacer(Modifier.height(6.dp))
            Text(
                "${peerName ?: "Mac"} · $peerBattery%",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Endpoint(icon: ImageVector, name: String, lit: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(92.dp)) {
        Box(
            Modifier
                .size(58.dp)
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

/** Linked: a spark runs the line, easing at each end like a hand-off. Not: a dim dashed gap. */
@Composable
private fun Filament(linked: Boolean, modifier: Modifier = Modifier) {
    val ember = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val t by rememberInfiniteTransition(label = "filament").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1800, easing = FastOutSlowInEasing), RepeatMode.Restart),
        label = "spark",
    )
    Canvas(modifier) {
        val y = size.height / 2
        if (linked) {
            drawLine(ember.copy(alpha = 0.35f), Offset(0f, y), Offset(size.width, y), strokeWidth = 2.dp.toPx())
            val x = size.width * t
            drawCircle(ember.copy(alpha = 0.25f), radius = 9.dp.toPx(), center = Offset(x, y))
            drawCircle(ember, radius = 4.dp.toPx(), center = Offset(x, y))
        } else {
            drawLine(
                muted.copy(alpha = 0.4f), Offset(0f, y), Offset(size.width, y),
                strokeWidth = 1.5.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 6.dp.toPx())),
            )
        }
    }
}

@Composable
private fun RecentRow(entry: ClipEntry, peerName: String?, onCopy: (ClipEntry) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(14.dp)
            .clickable { onCopy(entry) }
            .padding(14.dp),
    ) {
        Text(
            if (entry.fromSelf) "Copied here" else "From ${peerName ?: "your Mac"}",
            style = MaterialTheme.typography.labelSmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            if (entry.isImage) "Image" else entry.text.orEmpty(),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** One file on its way in or out: name, where it is going, a bar, and a way to stop it. */
@Composable
private fun TransferRow(
    transfer: TransferProgress,
    peerName: String?,
    onCancel: (String) -> Unit,
    onOpen: (String) -> Unit,
) {
    val peer = peerName ?: "your Mac"
    val status = when (transfer.state) {
        TransferProgress.State.Active ->
            (if (transfer.outgoing) "Sending to $peer · " else "Receiving from $peer · ") +
                "${percent(transfer)}%"
        TransferProgress.State.Sent -> "Waiting for $peer to confirm"
        TransferProgress.State.Done ->
            if (transfer.outgoing) "Sent to $peer" else "Saved to Downloads · tap to open"
        TransferProgress.State.Cancelled -> "Cancelled"
        TransferProgress.State.Failed -> "Didn't go through"
    }
    val openable = !transfer.outgoing && transfer.state == TransferProgress.State.Done
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(14.dp)
            .then(if (openable) Modifier.clickable { onOpen(transfer.transferId) } else Modifier)
            .padding(start = 14.dp, top = 12.dp, bottom = 12.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                transfer.name,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                status,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = if (transfer.state == TransferProgress.State.Failed) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
            if (!transfer.finished) {
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { percent(transfer) / 100f },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        if (!transfer.finished) {
            IconButton(onClick = { onCancel(transfer.transferId) }) {
                Icon(Icons.Filled.Close, contentDescription = "Cancel ${transfer.name}")
            }
        } else {
            Spacer(Modifier.size(10.dp))
        }
    }
}

private fun percent(transfer: TransferProgress): Int =
    if (transfer.total <= 0) 0 else (transfer.bytes * 100 / transfer.total).toInt().coerceIn(0, 100)

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
                .background(
                    if (sharing) MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
                    else MaterialTheme.colorScheme.surfaceVariant,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.ScreenShare,
                contentDescription = null,
                tint = if (sharing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(36.dp),
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            if (sharing) "Sharing with $mac" else "Show this screen on $mac",
            style = MaterialTheme.typography.titleLarge,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            when {
                sharing -> "Everything on this screen is visible on $mac. Stop any time from here or the notification."
                linked -> "Live over your Wi-Fi, straight to $mac. Nothing goes through the internet."
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
        Spacer(Modifier.height(100.dp))
    }
}
