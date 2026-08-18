package com.fuseos.app.ui.dashboard

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseWordmark
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun DashboardScreen() {
    val viewModel: DashboardViewModel = viewModel(factory = DashboardViewModel.Factory)
    val state by viewModel.state.collectAsState()
    val history by viewModel.history.collectAsState()
    var showPairing by remember { mutableStateOf(false) }

    if (showPairing) {
        PairingScreen(viewModel = viewModel, onClose = { showPairing = false })
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FuseWordmark()
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { viewModel.signOut() }) { Text("Sign out") }
        }
        Spacer(Modifier.height(28.dp))

        Text(
            "THIS DEVICE",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(8.dp))
        DeviceCard(
            name = state.selfDevice?.name ?: "This phone",
            subtitle = "This device · online",
            platform = "android",
            online = true,
            battery = state.selfDevice?.battery ?: viewModel.selfBattery(),
        )

        Spacer(Modifier.height(26.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Connected devices",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.weight(1f))
            Text(
                "${state.peers.size}",
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(12.dp))

        if (state.peers.isEmpty()) {
            Text(
                "No devices yet. Tap “Connect a device” to pair your Mac or phone.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (peer in state.peers) {
                    val presence = viewModel.presenceFor(peer)
                    // "connected" is stronger than "online": online means the server can
                    // see the peer, connected means we have a direct channel to it.
                    val status = when {
                        peer.id in state.connected -> "connected · direct"
                        presence.online -> "online"
                        else -> "offline"
                    }
                    DeviceCard(
                        name = peer.name,
                        subtitle = "${peer.platform} · $status",
                        platform = peer.platform,
                        online = presence.online,
                        battery = presence.battery,
                    )
                }
            }
        }

        state.error?.let {
            Spacer(Modifier.height(16.dp))
            ErrorBanner(it)
        }

        Spacer(Modifier.height(22.dp))
        FusePrimaryButton(text = "Connect a device", onClick = { showPairing = true })

        Spacer(Modifier.height(30.dp))
        ClipboardHistory(
            entries = history,
            connected = state.connected.isNotEmpty(),
            onCopy = { viewModel.copyToClipboard(it) },
        )
        Spacer(Modifier.height(12.dp))
    }
}

/**
 * Everything copied on this device or received from a peer, newest first.
 *
 * This is also the diagnostic for "sync isn't working": an item that appears here marked
 * "Copied here" but never shows up on the Mac places the failure on the LAN channel, not
 * on the clipboard capture.
 */
@Composable
private fun ClipboardHistory(
    entries: List<ClipEntry>,
    connected: Boolean,
    onCopy: (ClipEntry) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            "Clipboard",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.weight(1f))
        Text(
            if (connected) "syncing" else "not connected",
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.labelSmall,
            color = if (connected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
    Spacer(Modifier.height(12.dp))

    if (entries.isEmpty()) {
        Text(
            "Nothing yet. Copy something here — with FuseOS on screen, since Android only " +
                "lets the app in front read the clipboard — or copy on your Mac and it " +
                "lands here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        return
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (entry in entries) {
            ClipCard(entry = entry, onCopy = { onCopy(entry) })
        }
    }
}

@Composable
private fun ClipCard(entry: ClipEntry, onCopy: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(14.dp))
            .clickable(onClick = onCopy)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (entry.fromSelf) "Copied here" else "From your Mac",
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.weight(1f))
            Text(
                clockTime(entry.atUnixMs),
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(8.dp))

        val bytes = entry.imageBytes
        if (bytes != null) {
            // Decoded per entry and cached by it, so scrolling doesn't re-decode.
            val bitmap = remember(entry.id) {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }
            if (bitmap != null) {
                Image(
                    bitmap = bitmap,
                    contentDescription = "Copied image",
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(140.dp)
                        .clip(RoundedCornerShape(10.dp)),
                    contentScale = ContentScale.Crop,
                )
            } else {
                Text("Image", style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            Text(
                entry.text.orEmpty(),
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private fun clockTime(unixMs: Long): String =
    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(unixMs))

@Composable
internal fun DeviceCard(
    name: String,
    subtitle: String,
    platform: String,
    online: Boolean,
    battery: Int?,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = if (online) 0.14f else 0.07f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                glyph(platform),
                contentDescription = null,
                tint = if (online) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.size(14.dp))
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.SemiBold)
            Text(
                subtitle,
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.labelSmall,
                color = if (online) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (battery != null) {
            Text(
                "$battery%",
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                color = if (battery <= 20) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

internal fun glyph(platform: String): ImageVector =
    if (platform == "android") Icons.Filled.Smartphone else Icons.Filled.Computer
