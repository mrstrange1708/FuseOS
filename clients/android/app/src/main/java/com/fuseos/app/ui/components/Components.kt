package com.fuseos.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The FuseOS mark: a wired-through node and a lit ember node joined by a filament. */
@Composable
fun FuseMark(height: Dp = 22.dp) {
    val ring = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    Canvas(modifier = Modifier.size(width = height * 1.8f, height = height)) {
        val h = size.height
        val cy = h / 2f
        val r = h * 0.22f
        val stroke = h * 0.10f
        val leftX = r + stroke
        val rightX = size.width - r - stroke
        drawLine(ring.copy(alpha = 0.4f), Offset(leftX, cy), Offset(rightX, cy), strokeWidth = stroke)
        drawCircle(accent, radius = r * 0.5f, center = Offset(size.width / 2f, cy))
        drawCircle(ring, radius = r, center = Offset(leftX, cy), style = Stroke(width = stroke))
        drawCircle(accent, radius = r, center = Offset(rightX, cy))
    }
}

@Composable
fun FuseWordmark() {
    Row(verticalAlignment = Alignment.CenterVertically) {
        FuseMark(height = 22.dp)
        Spacer(Modifier.size(10.dp))
        Text(
            text = "Fuse",
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            fontSize = 18.sp,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = "OS",
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
            fontSize = 18.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
fun FuseTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    isPassword: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Next,
    onImeAction: () -> Unit = {},
    errorText: String? = null,
    enabled: Boolean = true,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { Text(label) },
            singleLine = true,
            enabled = enabled,
            isError = errorText != null,
            visualTransformation =
                if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
            keyboardActions = KeyboardActions(
                onNext = { onImeAction() },
                onDone = { onImeAction() },
                onGo = { onImeAction() },
            ),
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth(),
        )
        if (errorText != null) {
            Text(
                text = errorText,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.padding(start = 6.dp, top = 4.dp),
            )
        }
    }
}

@Composable
fun FusePrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    Button(
        onClick = onClick,
        enabled = enabled && !loading,
        shape = RoundedCornerShape(12.dp),
        modifier = modifier.fillMaxWidth().height(52.dp),
    ) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        } else {
            Text(text, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
fun ErrorBanner(message: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(
                MaterialTheme.colorScheme.error.copy(alpha = 0.10f),
                RoundedCornerShape(12.dp),
            )
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = message,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

@Composable
fun AuthSwitchRow(prompt: String, action: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = prompt,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyLarge,
        )
        TextButton(onClick = onClick, contentPadding = PaddingValues(horizontal = 6.dp)) {
            Text(action, fontWeight = FontWeight.SemiBold)
        }
    }
}

/**
 * The one card surface: translucent over the ember glow, with a hairline edge lit from
 * above. Every card in the app goes through here so they read as one material — the
 * Android twin of `glassCard()` on macOS.
 */
fun Modifier.glassCard(radius: Dp = 16.dp): Modifier = composed {
    val shape = RoundedCornerShape(radius)
    val scheme = MaterialTheme.colorScheme
    clip(shape)
        .background(scheme.surface.copy(alpha = 0.74f))
        .border(
            1.dp,
            Brush.verticalGradient(
                listOf(scheme.onSurface.copy(alpha = 0.12f), scheme.outlineVariant.copy(alpha = 0.35f)),
            ),
            shape,
        )
}

/**
 * The app's ground: the slate background with the ember glowing down from the top edge.
 * Translucent cards over a flat colour read as flat; this gives them something to sit on.
 */
fun Modifier.fuseBackground(): Modifier = composed {
    val base = MaterialTheme.colorScheme.background
    val glow = MaterialTheme.colorScheme.primary.copy(alpha = 0.20f)
    background(base).drawBehind {
        drawRect(
            Brush.radialGradient(
                listOf(glow, Color.Transparent),
                center = Offset(size.width / 2, -size.width * 0.15f),
                radius = size.width * 1.1f,
            ),
        )
    }
}
