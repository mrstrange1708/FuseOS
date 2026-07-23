package com.fuseos.app.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fuseos.app.ui.components.ErrorBanner
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseTextField
import kotlinx.coroutines.launch

private enum class PairMode { Show, Enter }

@Composable
fun PairingScreen(viewModel: DashboardViewModel, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf(PairMode.Show) }
    var code by remember { mutableStateOf<String?>(null) }
    var entered by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // When the other device redeems our code, the server pushes `paired`; close.
    LaunchedEffect(Unit) {
        viewModel.paired.collect { onClose() }
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

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ModeButton("Show a code", mode == PairMode.Show, Modifier.weight(1f)) {
                mode = PairMode.Show
                error = null
            }
            ModeButton("Enter a code", mode == PairMode.Enter, Modifier.weight(1f)) {
                mode = PairMode.Enter
                error = null
            }
        }
        Spacer(Modifier.height(22.dp))

        when (mode) {
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
            PairMode.Enter -> EnterCode(
                value = entered,
                onValueChange = { entered = it },
                busy = busy,
                onPair = {
                    val trimmed = entered.trim()
                    if (trimmed.isEmpty()) {
                        error = "Enter the pairing code."
                        return@EnterCode
                    }
                    busy = true
                    error = null
                    scope.launch {
                        try {
                            viewModel.claimPairing(trimmed)
                            onClose()
                        } catch (e: Exception) {
                            error = e.message ?: "Pairing failed."
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
        colors = if (selected) {
            ButtonDefaults.buttonColors()
        } else {
            ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
    ) {
        Text(label)
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
            Text(
                code,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
                    .padding(vertical = 22.dp),
                textAlign = TextAlign.Center,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                fontSize = 32.sp,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "Expires in 5 minutes · waiting for the other device…",
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
        Spacer(Modifier.height(18.dp))
        FuseTextField(
            value = value,
            onValueChange = onValueChange,
            label = "Pairing code",
            imeAction = ImeAction.Done,
            onImeAction = onPair,
        )
        Spacer(Modifier.height(18.dp))
        FusePrimaryButton(text = "Pair", onClick = onPair, loading = busy)
    }
}
