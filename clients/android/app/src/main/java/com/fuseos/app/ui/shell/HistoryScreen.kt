package com.fuseos.app.ui.shell

import com.fuseos.app.ui.components.glassCard
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fuseos.app.clipboard.ClipEntry
import com.fuseos.app.clipboard.HistoryWindow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Everything copied here or received from a peer, newest first, with a time window.
 *
 * The window is a *view* over what is held, not a retention policy — eviction is still the
 * size and count caps in `ClipboardSync`. So narrowing to 24 hours hides nothing
 * permanently, and widening back to All brings it straight back.
 */
@Composable
fun HistoryScreen(
    entries: List<ClipEntry>,
    peerName: String?,
    onCopy: (ClipEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    var window by remember { mutableStateOf(HistoryWindow.Day) }
    val shown = window.filter(entries)

    Column(modifier = modifier.fillMaxSize()) {
        Text(
            "Clipboard history",
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(horizontal = 24.dp),
        )
        Spacer(Modifier.height(14.dp))

        Row(
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            HistoryWindow.entries.forEach { option ->
                WindowChip(option.label, option == window) { window = option }
            }
        }
        Spacer(Modifier.height(16.dp))

        if (shown.isEmpty()) {
            EmptyHistory(hasAny = entries.isNotEmpty(), window = window)
        } else {
            LazyColumn(
                contentPadding = PaddingValues(start = 24.dp, end = 24.dp, bottom = 110.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(shown, key = { it.id }) { entry -> HistoryCard(entry, peerName, onCopy) }
            }
        }
    }
}

@Composable
private fun WindowChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(
                if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                },
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

@Composable
private fun EmptyHistory(hasAny: Boolean, window: HistoryWindow) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Text(
            // "Nothing in 24 hours" and "nothing ever" need different answers: one is a
            // filter to widen, the other is a feature to try.
            if (hasAny) {
                "Nothing copied in the last ${window.label.lowercase()}. Try a wider range."
            } else {
                "Nothing yet. Copy something on either device and it lands here."
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 32.dp, vertical = 40.dp),
        )
    }
}

@Composable
private fun HistoryCard(entry: ClipEntry, peerName: String?, onCopy: (ClipEntry) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(16.dp)
            .clickable { onCopy(entry) }
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (entry.fromSelf) "Copied here" else "From ${peerName ?: "your Mac"}",
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.weight(1f))
            Text(
                SimpleDateFormat("d MMM · h:mm a", Locale.getDefault()).format(Date(entry.atUnixMs)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(8.dp))

        val bytes = entry.imageBytes
        if (bytes != null) {
            val bitmap = remember(entry.id) {
                runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
            }
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = "Copied image",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(150.dp)
                        .clip(RoundedCornerShape(10.dp)),
                )
            } else {
                Text("Image", color = MaterialTheme.colorScheme.onSurfaceVariant)
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
