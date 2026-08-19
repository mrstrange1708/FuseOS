package com.fuseos.app.ui.shell

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.core.ConnectStage
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.app.ui.dashboard.DeviceCard

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
    modifier: Modifier = Modifier,
) {
    val connect = state.connect
    val peer = state.peers.firstOrNull { it.id == connect.peerId }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
    ) {
        LinkBanner(stage = connect.stage, peerName = peer?.name)
        Spacer(Modifier.height(20.dp))

        Text("Devices", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(10.dp))
        DeviceCard(
            name = state.selfDevice?.name ?: "This phone",
            subtitle = "This device · online",
            platform = "android",
            online = true,
            battery = selfBattery,
        )
        Spacer(Modifier.height(10.dp))
        state.peers.forEach { device ->
            DeviceCard(
                name = device.name,
                subtitle = when {
                    device.id in state.connected -> "${device.platform} · connected · direct"
                    state.presence[device.id]?.online == true -> "${device.platform} · online"
                    else -> "${device.platform} · offline"
                },
                platform = device.platform,
                online = device.id in state.connected,
                battery = peerBattery(device.id),
            )
            Spacer(Modifier.height(10.dp))
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

/** One line that answers "is it working right now". */
@Composable
private fun LinkBanner(stage: ConnectStage, peerName: String?) {
    val connected = stage == ConnectStage.Connected
    val message = when (stage) {
        ConnectStage.Connected -> "Linked to ${peerName ?: "your Mac"}"
        ConnectStage.Connecting -> "Connecting…"
        ConnectStage.DifferentNetwork -> "Different networks — join the same WiFi"
        ConnectStage.PeerOffline -> "${peerName ?: "Your Mac"} is offline"
        ConnectStage.Alone -> "No other device on this account yet"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(
                if (connected) {
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                },
            )
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(9.dp)
                .clip(CircleShape)
                .background(
                    if (connected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                ),
        )
        Spacer(Modifier.size(10.dp))
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = if (connected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

@Composable
private fun RecentRow(entry: ClipEntry, peerName: String?, onCopy: (ClipEntry) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(14.dp))
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

/**
 * A destination that exists in the bar but not yet in the product.
 *
 * Screen mirroring and remote control are out of scope for v1 (see CLAUDE.md) — they would
 * change the transport design, and clipboard and files come first. The slot is here so the
 * bar's shape is final and does not shift under people later.
 */
@Composable
fun ComingSoonScreen(
    title: String,
    detail: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(72.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(18.dp))
        Text(title, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        Text(
            detail,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Filled.Lock,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(14.dp),
            )
            Spacer(Modifier.size(6.dp))
            Text(
                "Coming after clipboard and files",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(100.dp))
    }
}
