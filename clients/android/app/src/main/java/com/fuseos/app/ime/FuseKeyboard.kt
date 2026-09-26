package com.fuseos.app.ime

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardReturn
import androidx.compose.material.icons.rounded.Backspace
import androidx.compose.material.icons.rounded.KeyboardCapslock
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.NorthEast
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.text.style.TextOverflow
import com.fuseos.app.clipboard.ClipEntry
import kotlinx.coroutines.delay

/** Shift has three states, and a two-state toggle makes typing "ABC" a chore. */
private enum class Shift { Off, Once, Locked }

private val LETTER_ROWS = listOf(
    "qwertyuiop",
    "asdfghjkl",
    "zxcvbnm",
)

private val SYMBOL_ROWS = listOf(
    "1234567890",
    "@#\$_&-+()/",
    "*\"':;!?",
)

/**
 * A plain QWERTY. Deliberately plain — see [FuseKeyboardService] for why this exists at
 * all. Two layers (letters and symbols), three shift states, and nothing else.
 */
@Composable
fun FuseKeyboard(
    onKey: (String) -> Unit,
    onBackspace: () -> Unit,
    onEnter: () -> Unit,
    clips: List<ClipEntry> = emptyList(),
    onSendClipboard: () -> Boolean = { false },
) {
    var symbols by remember { mutableStateOf(false) }
    var showClips by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf<Boolean?>(null) }
    var shift by remember { mutableStateOf(Shift.Off) }
    val scheme = MaterialTheme.colorScheme

    val rows = if (symbols) SYMBOL_ROWS else LETTER_ROWS

    /** One-shot shift falls back to Off after a key; a locked one stays. */
    fun type(character: String) {
        onKey(character)
        if (shift == Shift.Once) shift = Shift.Off
    }

    Column(
        Modifier
            .fillMaxWidth()
            .background(scheme.surfaceVariant)
            .navigationBarsPadding()
            .padding(horizontal = 4.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        // The strip that makes this a FuseOS keyboard: recent clips, and send-to-Mac.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StripButton(
                icon = Icons.Rounded.ContentPaste,
                label = if (showClips) "Keyboard" else "Clipboard",
                active = showClips,
            ) { showClips = !showClips }
            Spacer(Modifier.weight(1f))
            StripButton(
                icon = if (sent == true) Icons.Rounded.Check else Icons.Rounded.NorthEast,
                label = when (sent) {
                    true -> "Sent"
                    false -> "Nothing to send"
                    null -> "Send to Mac"
                },
                active = sent == true,
            ) { sent = onSendClipboard() }
        }
        LaunchedEffect(sent) {
            if (sent != null) {
                delay(1_500)
                sent = null
            }
        }

        if (showClips) {
            ClipList(clips) { text ->
                onKey(text)
                showClips = false
            }
            return@Column
        }

        rows.forEachIndexed { index, row ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                // The bottom letter row is shorter than the two above it, so shift and
                // backspace sit on its ends rather than in a row of their own.
                if (index == 2) {
                    ModifierKey(
                        icon = Icons.Rounded.KeyboardCapslock,
                        weight = 1.5f,
                        active = shift != Shift.Off,
                    ) {
                        shift = when (shift) {
                            Shift.Off -> Shift.Once
                            Shift.Once -> Shift.Locked
                            Shift.Locked -> Shift.Off
                        }
                    }
                }
                row.forEach { character ->
                    val label = if (!symbols && shift != Shift.Off) {
                        character.uppercaseChar().toString()
                    } else {
                        character.toString()
                    }
                    Key(label) { type(label) }
                }
                if (index == 2) {
                    ModifierKey(icon = Icons.Rounded.Backspace, weight = 1.5f, onClick = onBackspace)
                }
            }
        }

        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            ModifierKey(label = if (symbols) "ABC" else "?123", weight = 1.6f) {
                symbols = !symbols
            }
            Key(",", weight = 1f) { type(",") }
            Key(" ", weight = 5f) { type(" ") }
            Key(".", weight = 1f) { type(".") }
            ModifierKey(
                icon = Icons.AutoMirrored.Rounded.KeyboardReturn,
                weight = 1.6f,
                accent = true,
                onClick = onEnter,
            )
        }
    }
}

/** Recent clips as tap-to-paste rows, in the space the keys normally take. */
@Composable
private fun ClipList(clips: List<ClipEntry>, onPaste: (String) -> Unit) {
    val texts = clips.mapNotNull { it.text?.takeIf(String::isNotBlank) }.distinct().take(20)
    if (texts.isEmpty()) {
        Box(Modifier.fillMaxWidth().height(KEY_AREA), contentAlignment = Alignment.Center) {
            Text(
                "Copied text shows up here, from this phone and your Mac.",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    LazyColumn(
        Modifier.fillMaxWidth().height(KEY_AREA),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(texts) { text ->
            Text(
                text.lines().joinToString(" ") { it.trim() },
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surface)
                    .clickable { onPaste(text) }
                    .padding(horizontal = 12.dp, vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun StripButton(icon: ImageVector, label: String, active: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        Modifier
            .clip(RoundedCornerShape(18.dp))
            .background(if (active) scheme.primary.copy(alpha = 0.18f) else scheme.surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, contentDescription = null, tint = if (active) scheme.primary else scheme.onSurface, modifier = Modifier.height(18.dp))
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (active) scheme.primary else scheme.onSurface)
    }
}

/** Four rows of 46 dp keys and their gaps — the clip list takes the same space. */
private val KEY_AREA = 202.dp

@Composable
private fun RowScope.Key(label: String, weight: Float = 1f, onClick: () -> Unit) {
    KeySurface(weight = weight, onClick = onClick) {
        Text(
            text = label,
            fontSize = 18.sp,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun RowScope.ModifierKey(
    label: String? = null,
    icon: ImageVector? = null,
    weight: Float = 1f,
    active: Boolean = false,
    accent: Boolean = false,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val background = when {
        accent -> scheme.primary
        active -> scheme.primary.copy(alpha = 0.22f)
        else -> scheme.outlineVariant
    }
    val foreground = if (accent) scheme.onPrimary else scheme.onSurface
    KeySurface(weight = weight, background = background, onClick = onClick) {
        when {
            icon != null -> Icon(icon, contentDescription = label, tint = foreground)
            label != null -> Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = foreground)
        }
    }
}

@Composable
private fun RowScope.KeySurface(
    weight: Float,
    background: Color = MaterialTheme.colorScheme.surface,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = Modifier
            .weight(weight)
            .height(46.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
        content = { content() },
    )
}
