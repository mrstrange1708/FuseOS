package com.fuseos.app.ui.shell

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.file.TransferProgress
import com.fuseos.app.ui.components.glassCard
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The app's one card: a titled panel holding rows. Grouping rows into panels, rather than
 * floating every row as its own card, is what makes a screen read as organised. The
 * Android twin of `Panel` on macOS.
 */
@Composable
fun Panel(
    title: String? = null,
    action: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .glassCard(20.dp)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        if (title != null) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(start = 4.dp, end = 4.dp, bottom = 6.dp),
            ) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                action?.invoke()
            }
        }
        content()
    }
}

/** A small rounded tile holding an icon — the leading mark of every row. */
@Composable
fun IconTile(icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary) {
    Box(
        Modifier
            .size(38.dp)
            .clip(RoundedCornerShape(11.dp))
            .background(tint.copy(alpha = 0.13f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(19.dp))
    }
}

/** One clipboard entry: what, where from, when. Tap to put it back on the clipboard. */
@Composable
fun ClipListRow(entry: ClipEntry, peerName: String?, onCopy: (ClipEntry) -> Unit) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable { onCopy(entry) }
            .padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val bytes = entry.imageBytes
        val bitmap = remember(entry.id) {
            bytes?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
        }
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Copied image",
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)),
            )
        } else {
            val text = entry.text.orEmpty()
            IconTile(
                if (text.startsWith("http://") || text.startsWith("https://")) Icons.Filled.Link else Icons.AutoMirrored.Filled.Notes,
                tint = if (entry.fromSelf) muted else MaterialTheme.colorScheme.primary,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                if (entry.isImage) "Image" else entry.text.orEmpty().lines().joinToString("  ") { it.trim() },
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                (if (entry.fromSelf) "Copied here" else "From ${peerName ?: "your Mac"}") +
                    " · " + SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(entry.atUnixMs)),
                style = MaterialTheme.typography.bodySmall,
                color = muted,
                maxLines = 1,
            )
        }
    }
}

/** One file on its way in or out: name, where it is going, a bar, and a way to stop it. */
@Composable
fun TransferListRow(
    transfer: TransferProgress,
    peerName: String?,
    onCancel: (String) -> Unit,
    onOpen: (String) -> Unit,
) {
    val peer = peerName ?: "your Mac"
    val percent = if (transfer.total <= 0) 0 else (transfer.bytes * 100 / transfer.total).toInt().coerceIn(0, 100)
    val status = when (transfer.state) {
        TransferProgress.State.Active -> (if (transfer.outgoing) "To $peer · " else "From $peer · ") + "$percent%"
        TransferProgress.State.Sent -> "Waiting for $peer to confirm"
        TransferProgress.State.Done -> if (transfer.outgoing) "Sent to $peer" else "Saved to Downloads · tap to open"
        TransferProgress.State.Cancelled -> "Cancelled"
        TransferProgress.State.Failed -> "Didn't go through"
    }
    val openable = !transfer.outgoing && transfer.state == TransferProgress.State.Done
    val failed = transfer.state == TransferProgress.State.Failed
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .then(if (openable) Modifier.clickable { onOpen(transfer.transferId) } else Modifier)
            .padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(
            if (transfer.outgoing) Icons.Filled.ArrowUpward else Icons.Filled.ArrowDownward,
            tint = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(transfer.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (!transfer.finished) {
                Spacer(Modifier.height(6.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.outlineVariant),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(percent / 100f)
                            .height(4.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary),
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                status,
                style = MaterialTheme.typography.bodySmall,
                color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (!transfer.finished) {
            IconButton(onClick = { onCancel(transfer.transferId) }) {
                Icon(Icons.Filled.Close, contentDescription = "Cancel ${transfer.name}", modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** A dot and a few words: where the link stands. */
@Composable
fun StatusPill(text: String, lit: Boolean) {
    val tint = if (lit) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.12f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(tint))
        Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = tint)
    }
}

/** A settings row inside a panel: what it is, one line on why, and what it is set to. */
@Composable
fun SettingItem(
    title: String,
    detail: String,
    onClick: () -> Unit,
    trailing: String? = null,
    trailingLit: Boolean = false,
    destructive: Boolean = false,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(2.dp))
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (trailing != null) {
            Spacer(Modifier.width(12.dp))
            StatusPill(trailing, trailingLit)
        }
    }
}
