package com.fuseos.app.ui.theme

import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.MutableStateFlow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import android.content.Context
import androidx.compose.animation.core.spring
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// FuseOS palette — "Filament": cool slate devices, one warm ember accent (the link).
val Ember = Color(0xFFE85D2A)
val EmberDark = Color(0xFFFF7A45)

/** The website's second warm note: tails, beads and the end of every gradient. */
val Amber = Color(0xFFFFB347)

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

/** You → Appearance. System follows the phone, and is the default. */
enum class ThemeMode { System, Light, Dark }

/** The saved [ThemeMode], as a flow so every window — app, trackpad, island — follows a change at once. */
object ThemePreference {
    private const val PREFS = "appearance"
    private const val KEY = "mode"
    private var mode: MutableStateFlow<ThemeMode>? = null

    fun flow(context: Context): StateFlow<ThemeMode> = mode ?: MutableStateFlow(
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?.let { saved -> ThemeMode.entries.firstOrNull { it.name == saved } } ?: ThemeMode.System,
    ).also { mode = it }

    fun set(context: Context, value: ThemeMode) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, value.name).apply()
        (flow(context) as MutableStateFlow).value = value
    }
}

@Composable
fun FuseOSTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val mode by ThemePreference.flow(context).collectAsState()
    val darkTheme = when (mode) {
        ThemeMode.System -> isSystemInDarkTheme()
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
    }
    // The system bars follow the app's choice, not the phone's: dark icons on a light app.
    (context as? ComponentActivity)?.let { activity ->
        LaunchedEffect(activity, darkTheme) {
            val bars = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT) { darkTheme }
            activity.enableEdgeToEdge(statusBarStyle = bars, navigationBarStyle = bars)
        }
    }
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = FuseTypography,
        content = content,
    )
}

/**
 * One motion vocabulary, in Apple's terms: a spring's *response* (seconds to reach the
 * target) and *damping* (1 = no overshoot). Compose takes stiffness, which for a unit mass
 * is (2π / response)². Critically damped by default; a little bounce only where something
 * arrives with momentum. Springs start from the current value, so all of these interrupt
 * cleanly mid-flight. The twin of `FuseMotion` on macOS.
 */
object FuseMotion {
    /** Moves and state changes: response 0.35 s, no overshoot. */
    fun <T> standard() = spring<T>(dampingRatio = 1f, stiffness = 322f)

    /** Press feedback: response 0.2 s — quick enough to read as contact. */
    fun <T> quick() = spring<T>(dampingRatio = 1f, stiffness = 987f)

    /** Something landed — a clip crossed, a device answered: response 0.4 s, damping 0.8. */
    fun <T> arrive() = spring<T>(dampingRatio = 0.8f, stiffness = 247f)
}
