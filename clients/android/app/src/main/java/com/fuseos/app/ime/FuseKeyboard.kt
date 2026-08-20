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
) {
    var symbols by remember { mutableStateOf(false) }
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
