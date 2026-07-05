package com.fuseos.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// FuseOS palette — "Filament": cool slate devices, one warm ember accent (the link).
val Ember = Color(0xFFE85D2A)
val EmberDark = Color(0xFFFF7A45)

private val LightColors = lightColorScheme(
    primary = Ember,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFFCE3D7),
    onPrimaryContainer = Color(0xFF7A2E12),
    background = Color(0xFFF1F3F7),
    onBackground = Color(0xFF14171F),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF14171F),
    surfaceVariant = Color(0xFFF2F4F8),
    onSurfaceVariant = Color(0xFF59616F),
    outline = Color(0xFFCDD3DD),
    outlineVariant = Color(0xFFE1E4EB),
    error = Color(0xFFC0341B),
    onError = Color(0xFFFFFFFF),
)

private val DarkColors = darkColorScheme(
    primary = EmberDark,
    onPrimary = Color(0xFF3A1305),
    primaryContainer = Color(0xFF5A2712),
    onPrimaryContainer = Color(0xFFFFD3BC),
    background = Color(0xFF0C0E14),
    onBackground = Color(0xFFECEFF4),
    surface = Color(0xFF161922),
    onSurface = Color(0xFFECEFF4),
    surfaceVariant = Color(0xFF1C202A),
    onSurfaceVariant = Color(0xFF98A0AD),
    outline = Color(0xFF343B47),
    outlineVariant = Color(0xFF262B35),
    error = Color(0xFFFF8A75),
    onError = Color(0xFF3A0D06),
)

@Composable
fun FuseOSTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = FuseTypography,
        content = content,
    )
}
