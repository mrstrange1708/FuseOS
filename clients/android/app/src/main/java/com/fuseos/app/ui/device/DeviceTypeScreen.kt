package com.fuseos.app.ui.device

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fuseos.app.data.ServiceLocator
import com.fuseos.app.ui.components.FusePrimaryButton
import com.fuseos.app.ui.components.FuseWordmark
import kotlinx.coroutines.launch

/** The device kinds a user can pick. Only Android and macOS are supported in v1. */
enum class DeviceType(val id: String, val label: String, val available: Boolean) {
    ANDROID("android", "Android", true),
    MACOS("macos", "macOS", true),
    IOS("ios", "Apple iOS phone", false),
    WINDOWS("windows", "Windows", false),
}

/**
 * Post-login step: "What device is this?" Picking a supported type advances to
 * Home; the unsupported ones just say "Coming soon".
 */
@Composable
fun DeviceTypeScreen() {
    val repo = ServiceLocator.authRepository
    val scope = rememberCoroutineScope()
    var comingSoon by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.Start,
    ) {
        Spacer(Modifier.height(40.dp))
        FuseWordmark()
        Spacer(Modifier.height(36.dp))

        Text("What device is this?", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(6.dp))
        Text(
            "Choose the platform you're setting up.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(28.dp))

        DeviceType.entries.forEach { device ->
            FusePrimaryButton(
                text = device.label,
                onClick = {
                    if (device.available) {
                        scope.launch { repo.setDeviceType(device.id) }
                    } else {
                        comingSoon = device.label
                    }
                },
            )
            Spacer(Modifier.height(12.dp))
        }

        if (comingSoon != null) {
            Spacer(Modifier.height(4.dp))
            Text(
                "$comingSoon — Coming soon",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
