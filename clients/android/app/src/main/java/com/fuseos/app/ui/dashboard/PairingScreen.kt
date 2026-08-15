package com.fuseos.app.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fuseos.app.core.PairingCode
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FusePrimaryButton
import kotlinx.coroutines.launch

private enum class PairMode(val label: String) {
    Scan("Scan QR"),
    Enter("Enter code"),
    Show("Show code"),
}

@Composable
fun PairingScreen(viewModel: DashboardViewModel, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    // Scanning is the fast path — the Mac shows the QR, so the phone opens on the camera.
    var mode by remember { mutableStateOf(PairMode.Scan) }
    var code by remember { mutableStateOf<String?>(null) }
    var entered by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // When the other device redeems our code, the server pushes `paired`; close.
    LaunchedEffect(Unit) {
        viewModel.paired.collect { onClose() }
    }

    fun pair(rawCode: String) {
        val normalized = PairingCode.normalize(rawCode)
        if (normalized.length != PairingCode.LENGTH) {
            error = "Enter all ${PairingCode.LENGTH} characters of the code."
            return
        }
        if (busy) return // the code field auto-submits on the last character
        busy = true
        error = null
        scope.launch {
            try {
                viewModel.claimPairing(normalized)
                onClose()
            } catch (e: Exception) {
                error = e.message ?: "Pairing failed."
            }
            busy = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Connect a device",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClose) { Text("Close") }
        }
        Spacer(Modifier.height(18.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PairMode.entries.forEach { option ->
                ModeButton(option.label, mode == option, Modifier.weight(1f)) {
                    mode = option
                    error = null
                }
            }
        }
        Spacer(Modifier.height(22.dp))

        when (mode) {
            PairMode.Scan -> ScanCode(busy = busy, onCode = ::pair)
            PairMode.Enter -> EnterCode(
                value = entered,
                onValueChange = { entered = it },
                busy = busy,
                onPair = { pair(entered) },
            )
            PairMode.Show -> ShowCode(
                code = code,
                busy = busy,
                onGenerate = {
                    busy = true
                    error = null
                    scope.launch {
                        try {
                            code = viewModel.initiatePairing()
                        } catch (e: Exception) {
                            error = e.message ?: "Could not create a code."
                        }
                        busy = false
                    }
                },
            )
        }

        error?.let {
            Spacer(Modifier.height(16.dp))
            ErrorBanner(it)
        }
    }
}

@Composable
private fun ModeButton(label: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 6.dp),
        colors = if (selected) {
            ButtonDefaults.buttonColors()
        } else {
            ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1)
    }
}

@Composable
private fun ScanCode(busy: Boolean, onCode: (String) -> Unit) {
    Column {
        Text(
            "Open “Connect a device” on your Mac and scan the QR code it shows.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(18.dp))
        QrScanner(onCode = onCode)
        if (busy) {
            Spacer(Modifier.height(14.dp))
            Text(
                "Pairing…",
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ShowCode(code: String?, busy: Boolean, onGenerate: () -> Unit) {
    Column {
        Text(
            "Show this code on your other device and enter it there.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))
        if (code != null) {
            CodeCells(code = PairingCode.normalize(code), activeIndex = null)
            Spacer(Modifier.height(14.dp))
            Text(
                "Expires in 5 minutes · waiting for the other device…",
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            FusePrimaryButton(text = "Generate a code", onClick = onGenerate, loading = busy)
        }
    }
}

@Composable
private fun EnterCode(
    value: String,
    onValueChange: (String) -> Unit,
    busy: Boolean,
    onPair: () -> Unit,
) {
    Column {
        Text(
            "Enter the code shown on your other device.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))
        CodeField(value = value, onValueChange = onValueChange, onComplete = onPair)
        Spacer(Modifier.height(20.dp))
        FusePrimaryButton(text = "Pair", onClick = onPair, loading = busy)
    }
}

/**
 * The code as `XXXX-XXXX`, one box per character. [activeIndex] lights the box the next
 * keystroke will fill; null for a read-only display. Mirrors `CodeCells` on macOS.
 */
@Composable
private fun CodeCells(code: String, activeIndex: Int?) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(PairingCode.LENGTH) { index ->
            if (index == 4) {
                Text(
                    "-",
                    modifier = Modifier.padding(horizontal = 5.dp),
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 20.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            val active = index == activeIndex
            Box(
                modifier = Modifier
                    .padding(horizontal = 3.dp)
                    .width(34.dp)
                    .height(48.dp)
                    .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(10.dp))
                    .border(
                        width = if (active) 2.dp else 1.dp,
                        color = if (active) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.outlineVariant
                        },
                        shape = RoundedCornerShape(10.dp),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    code.getOrNull(index)?.toString().orEmpty(),
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 22.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

/**
 * Eight boxes that behave like one text field: a real (invisible) [BasicTextField] takes
 * the keystrokes — so the keyboard, paste and backspace all work — while the cells draw
 * the state. Everything typed goes through [PairingCode.normalize], so lowercase becomes
 * uppercase and separators are dropped as you type.
 */
@Composable
private fun CodeField(value: String, onValueChange: (String) -> Unit, onComplete: () -> Unit) {
    val focusRequester = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    BasicTextField(
        value = value,
        onValueChange = { raw ->
            val normalized = PairingCode.normalize(raw)
            onValueChange(normalized)
            if (normalized.length == PairingCode.LENGTH) onComplete()
        },
        modifier = Modifier
            .fillMaxWidth()
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused },
        textStyle = TextStyle(color = Color.Transparent),
        cursorBrush = SolidColor(Color.Transparent),
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Ascii,
            capitalization = KeyboardCapitalization.Characters,
            imeAction = ImeAction.Done,
        ),
        keyboardActions = KeyboardActions(onDone = { onComplete() }),
        // The field itself renders nothing; the boxes are the whole UI.
        decorationBox = {
            CodeCells(
                code = value,
                activeIndex = if (focused) value.length.coerceAtMost(PairingCode.LENGTH - 1) else null,
            )
        },
    )
}
