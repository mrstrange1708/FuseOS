package com.fuseos.app.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fuseos.app.ui.dashboard.DashboardViewModel
import com.fuseos.app.ui.dashboard.DeviceCard

/**
 * Account, the devices on it, and the way out.
 *
 * The device list lives here rather than on its own tab because it is reference material:
 * people check it when something is wrong, not on every visit. Home already answers the
 * everyday question of whether the link is up.
 */
@Composable
fun ProfileScreen(
    email: String?,
    state: DashboardViewModel.UiState,
    peerBattery: (String) -> Int?,
    onPairDevice: () -> Unit,
    onBatterySettings: () -> Unit,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    email?.take(1)?.uppercase() ?: "?",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Spacer(Modifier.size(14.dp))
            Column {
                Text(
                    email ?: "Signed in",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "${state.peers.size + 1} device${if (state.peers.isEmpty()) "" else "s"} · " +
                        "${state.connected.size} linked",
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Spacer(Modifier.height(26.dp))
        Text("Your devices", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(10.dp))

        DeviceCard(
            name = state.selfDevice?.name ?: "This phone",
            subtitle = "This device",
            platform = "android",
            online = true,
            battery = null,
        )
        state.peers.forEach { device ->
            Spacer(Modifier.height(10.dp))
            DeviceCard(
                name = device.name,
                subtitle = if (device.id in state.connected) "connected · direct" else "not connected",
                platform = device.platform,
                online = device.id in state.connected,
                battery = peerBattery(device.id),
            )
        }

        Spacer(Modifier.height(14.dp))
        SettingRow("Pair another device", "Scan a code shown on the other device", onPairDevice)
        Spacer(Modifier.height(10.dp))
        SettingRow(
            "Background permission",
            // Naming the real cause: on these phones the OS, not the app, is what stops
            // sync when the screen goes off.
            "Some phones freeze apps when the screen is off. Allow background activity to keep the link up.",
            onBatterySettings,
        )
        Spacer(Modifier.height(10.dp))
        SettingRow("Sign out", "Clears this device's session and clipboard history", onSignOut)

        Spacer(Modifier.height(120.dp))
    }
}

@Composable
private fun SettingRow(title: String, detail: String, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(16.dp),
    ) {
        Text(title, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(3.dp))
        Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
